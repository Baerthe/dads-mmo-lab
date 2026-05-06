#!/bin/bash
# ============================================================
#  Dad's MMO Lab — WoW Server Setup Wizard
#  The all-in-one installer for every WoW experience
#
#  https://github.com/DadsMmoLab/dads-mmo-lab
#
#  Version: 1.0.0
#
#  Usage:
#    chmod +x install-wow.sh
#    ./install-wow.sh
#
#  What this does:
#    1. Guides you through choosing your server type
#    2. Lets you pick compatible modules
#    3. Shows a summary before installing
#    4. Installs everything automatically
#    5. Creates as many accounts as you want
#    6. Sets up the Gaming Mode launcher
# ============================================================

WIZARD_VERSION="1.0.0"

set -o pipefail

# ─────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

print_header() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}${BOLD}         ⚙️  DAD'S MMO LAB                        ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}         WoW Server Setup Wizard                  ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${BLUE}         github.com/DadsMmoLab/dads-mmo-lab       ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${YELLOW}         Version ${WIZARD_VERSION}                              ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}${BOLD} $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }

ask_yes_no() {
    while true; do
        echo -e "${WHITE}$1 (y/n): ${NC}"
        read -r answer
        case $answer in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer y or n.";;
        esac
    done
}

press_enter() {
    echo ""
    echo -e "${WHITE}Press ENTER to continue...${NC}"
    read -r
}

# ─────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────
INSTALL_DIR="$HOME/wow-server"

# Server type selected
SERVER_TYPE=""
SERVER_NAME=""
SERVER_DIR=""

# Module selections
MOD_AHBOT=false
MOD_PROGRESSION=false
MOD_DUNGEON_MASTER=false
MOD_SOLOCRAFT=false
MOD_BOT_WANDER=false

# Build method (for NPCBots/Playerbots)
BUILD_METHOD=""

# ─────────────────────────────────────────
# SYSTEM CHECKS
# ─────────────────────────────────────────
check_system() {
    print_step "Checking System Requirements"

    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        print_error "This script requires Linux (SteamOS). Are you in Desktop Mode?"
        exit 1
    fi
    print_success "Linux detected"

    AVAILABLE_GB=$(df -BG "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' | tr -d ' ')
    if [ -n "$AVAILABLE_GB" ] && [ "$AVAILABLE_GB" -lt 15 ] 2>/dev/null; then
        print_error "Not enough disk space. You have ${AVAILABLE_GB}GB free, need at least 15GB."
        exit 1
    fi
    print_success "Disk space OK (${AVAILABLE_GB:-unknown}GB available)"

    if ! ping -c 1 github.com &>/dev/null; then
        print_error "No internet connection. Please connect and try again."
        exit 1
    fi
    print_success "Internet connection OK"
}

# ─────────────────────────────────────────
# INSTALL DOCKER
# ─────────────────────────────────────────
install_docker() {
    if command -v docker &>/dev/null && docker ps &>/dev/null 2>&1; then
        print_success "Docker already installed and running"
        return 0
    fi

    print_info "Installing Docker..."

    if command -v steamos-readonly &>/dev/null; then
        sudo steamos-readonly disable
    fi

    # Fix pacman keyring
    sudo rm -rf /etc/pacman.d/gnupg 2>/dev/null || true
    sudo pacman-key --init 2>/dev/null || true
    sudo pacman-key --populate archlinux 2>/dev/null || true
    sudo pacman-key --populate holo 2>/dev/null || true

    if command -v steamos-devmode &>/dev/null; then
        sudo steamos-devmode enable 2>/dev/null || true
    fi

    sudo pacman -Sy --noconfirm archlinux-keyring 2>/dev/null || true
    sudo pacman -Sy --noconfirm docker docker-compose

    sudo usermod -aG docker "$USER"
    sleep 2
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable docker 2>/dev/null || true
    sudo systemctl start docker 2>/dev/null || true
    sleep 3

    if ! docker ps &>/dev/null 2>&1; then
        if sudo docker ps &>/dev/null 2>&1; then
            function docker() { sudo docker "$@"; }
            export -f docker 2>/dev/null || true
        else
            print_error "Docker failed to start. Try rebooting and running again."
            exit 1
        fi
    fi

    print_success "Docker installed!"
}

install_git() {
    if command -v git &>/dev/null; then
        print_success "Git already installed"
        return 0
    fi
    print_info "Installing Git..."
    sudo pacman -Sy --noconfirm git 2>/dev/null || \
    sudo apt-get install -y git 2>/dev/null || true
    print_success "Git installed!"
}

# ─────────────────────────────────────────
# STEP 1 — CHOOSE SERVER TYPE
# ─────────────────────────────────────────
choose_server_type() {
    print_header
    print_step "STEP 1/6 — Choose Your Experience"

    echo ""
    echo -e "${WHITE}${BOLD}What kind of WoW server do you want?${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} ${WHITE}${BOLD}⚔️  Base WoW${NC}"
    echo -e "     Clean server — just you and the world"
    echo -e "     ${GREEN}Great for Solocraft!${NC} Scale dungeons to 1 player"
    echo -e "     ${GREEN}Lightest on resources — fastest install (~30 mins)${NC}"
    echo ""
    echo -e "  ${CYAN}2)${NC} ${WHITE}${BOLD}👥 NPCBots${NC}"
    echo -e "     Hire AI companions to join your party"
    echo -e "     Perfect for dungeons, raids and leveling together"
    echo -e "     ${YELLOW}⚠️  Compiles from source OR uses pre-built images${NC}"
    echo ""
    echo -e "  ${CYAN}3)${NC} ${WHITE}${BOLD}🌍 Playerbots${NC}"
    echo -e "     Hundreds of AI players roam the world freely"
    echo -e "     Quest, dungeon, raid — Azeroth feels truly alive"
    echo -e "     ${YELLOW}⚠️  Compiles from source (2-4 hours)${NC}"
    echo ""

    while true; do
        echo -e "${WHITE}Your choice (1-3): ${NC}"
        read -r choice
        case "$choice" in
            1)
                SERVER_TYPE="base"
                SERVER_NAME="Base WoW"
                SERVER_DIR="$HOME/wow-server"
                break
                ;;
            2)
                SERVER_TYPE="npcbots"
                SERVER_NAME="NPCBots WoW"
                SERVER_DIR="$HOME/wow-server-npcbots"
                break
                ;;
            3)
                SERVER_TYPE="playerbots"
                SERVER_NAME="Playerbots WoW"
                SERVER_DIR="$HOME/wow-server-playerbots"
                break
                ;;
            *)
                echo "Please enter 1, 2 or 3."
                ;;
        esac
    done

    print_success "Selected: $SERVER_NAME"

    # For NPCBots offer pre-built vs compile
    if [ "$SERVER_TYPE" = "npcbots" ]; then
        echo ""
        echo -e "${WHITE}${BOLD}How do you want to install NPCBots?${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC} ${GREEN}${BOLD}⚡ Fast Install (~10 minutes)${NC}"
        echo -e "     Uses pre-built images from GitHub"
        echo -e "     Recommended for most users"
        echo ""
        echo -e "  ${CYAN}2)${NC} ${YELLOW}${BOLD}🔨 Compile from Source (2-4 hours)${NC}"
        echo -e "     Builds everything on your Steam Deck"
        echo -e "     For power users — leave plugged in overnight"
        echo ""

        while true; do
            echo -e "${WHITE}Your choice (1-2): ${NC}"
            read -r build_choice
            case "$build_choice" in
                1) BUILD_METHOD="prebuilt"; break ;;
                2) BUILD_METHOD="compile"; break ;;
                *) echo "Please enter 1 or 2." ;;
            esac
        done
    fi

    if [ "$SERVER_TYPE" = "playerbots" ]; then
        BUILD_METHOD="compile"
        echo ""
        print_warning "Playerbots requires compiling from source — 2-4 hours."
        print_info "Make sure your Steam Deck is plugged in!"
        press_enter
    fi
}

# ─────────────────────────────────────────
# STEP 2 — CHOOSE MODULES
# ─────────────────────────────────────────
choose_modules() {
    print_header
    print_step "STEP 2/6 — Choose Your Modules"

    echo ""
    echo -e "${WHITE}These optional modules add extra features to your server.${NC}"
    echo -e "${WHITE}Pick what sounds good to you!${NC}"
    echo ""

    # AH Bot — available for all server types
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}${BOLD}💰 Auction House Bot${NC}"
    echo -e "  Populates all three Auction Houses with a living economy"
    echo -e "  Buy and sell items just like a real server"
    if ask_yes_no "  Install AH Bot?"; then
        MOD_AHBOT=true
        print_success "AH Bot added!"
    fi
    echo ""

    # Individual Progression — all server types
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}${BOLD}📈 Individual Progression${NC}"
    echo -e "  Start in Vanilla — unlock TBC then WotLK as you progress"
    echo -e "  Experience the full WoW story in order"
    if ask_yes_no "  Install Individual Progression?"; then
        MOD_PROGRESSION=true
        print_success "Individual Progression added!"
    fi
    echo ""

    # Dungeon Master — all server types
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}${BOLD}🏰 Dungeon Master${NC}"
    echo -e "  Procedural dungeon challenges with roguelike buffs"
    echo -e "  Extra incentive and variety for dungeon runners"
    if ask_yes_no "  Install Dungeon Master?"; then
        MOD_DUNGEON_MASTER=true
        print_success "Dungeon Master added!"
    fi
    echo ""

    # Solocraft — only for Base WoW
    if [ "$SERVER_TYPE" = "base" ]; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${WHITE}${BOLD}☀️  Solocraft${NC}"
        echo -e "  ${GREEN}Perfect for Base WoW!${NC}"
        echo -e "  Dynamically scales dungeon and raid difficulty for 1 player"
        echo -e "  Clear Molten Core SOLO — no bots needed"
        if ask_yes_no "  Install Solocraft?"; then
            MOD_SOLOCRAFT=true
            print_success "Solocraft added!"
        fi
        echo ""
    fi

    # Bot Wandering — only for NPCBots
    if [ "$SERVER_TYPE" = "npcbots" ]; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${WHITE}${BOLD}🤖 Wandering Bots (500 bots)${NC}"
        echo -e "  AI bots roam the open world — Azeroth feels populated"
        echo -e "  See bots questing, fighting and exploring everywhere"
        if ask_yes_no "  Enable wandering bots?"; then
            MOD_BOT_WANDER=true
            print_success "Wandering Bots enabled!"
        fi
        echo ""
    fi
}

# ─────────────────────────────────────────
# STEP 3 — SUMMARY AND CONFIRM
# ─────────────────────────────────────────
show_summary() {
    print_header
    print_step "STEP 3/6 — Your Setup Summary"

    echo ""
    echo -e "  ${WHITE}${BOLD}Server:${NC}   ${CYAN}$SERVER_NAME${NC}"
    echo -e "  ${WHITE}${BOLD}Folder:${NC}   ${CYAN}$SERVER_DIR${NC}"

    if [ -n "$BUILD_METHOD" ]; then
        if [ "$BUILD_METHOD" = "prebuilt" ]; then
            echo -e "  ${WHITE}${BOLD}Install:${NC}  ${GREEN}Fast (~10 minutes) — pre-built images${NC}"
        else
            echo -e "  ${WHITE}${BOLD}Install:${NC}  ${YELLOW}Compile from source (2-4 hours)${NC}"
        fi
    else
        echo -e "  ${WHITE}${BOLD}Install:${NC}  ${GREEN}Fast (~30 minutes)${NC}"
    fi

    echo ""
    echo -e "  ${WHITE}${BOLD}Modules:${NC}"
    local any_module=false

    [ "$MOD_AHBOT" = true ]        && echo -e "    ${GREEN}✅${NC} Auction House Bot" && any_module=true
    [ "$MOD_PROGRESSION" = true ]  && echo -e "    ${GREEN}✅${NC} Individual Progression" && any_module=true
    [ "$MOD_DUNGEON_MASTER" = true ] && echo -e "    ${GREEN}✅${NC} Dungeon Master" && any_module=true
    [ "$MOD_SOLOCRAFT" = true ]    && echo -e "    ${GREEN}✅${NC} Solocraft" && any_module=true
    [ "$MOD_BOT_WANDER" = true ]   && echo -e "    ${GREEN}✅${NC} Wandering Bots (500)" && any_module=true
    [ "$any_module" = false ]      && echo -e "    ${YELLOW}None selected${NC}"

    echo ""

    if [ "$BUILD_METHOD" = "compile" ]; then
        echo -e "${YELLOW}  ⚠️  COMPILATION WARNING:${NC}"
        echo -e "  This will take 2-4 hours on your Steam Deck."
        echo -e "  Keep it plugged in and don't let it sleep!"
        echo ""
    fi

    if ! ask_yes_no "Ready to build your server?"; then
        echo ""
        echo -e "${WHITE}No problem! Run this script again when you're ready.${NC}"
        exit 0
    fi
}

# ─────────────────────────────────────────
# STEP 4 — INSTALL SERVER
# ─────────────────────────────────────────
install_server() {
    print_header
    print_step "STEP 4/6 — Installing Your Server"

    # Install dependencies
    print_info "Checking dependencies..."
    install_docker
    install_git

    # Remove existing installation if present
    if [ -d "$SERVER_DIR" ]; then
        print_warning "Existing installation found at $SERVER_DIR"
        if ask_yes_no "Remove it and start fresh?"; then
            docker compose -f "$SERVER_DIR/docker-compose.yml" down -v 2>/dev/null || true
            sudo rm -rf "$SERVER_DIR"
        fi
    fi

    case "$SERVER_TYPE" in

        # ── BASE WOW ──────────────────────────────
        base)
            print_info "Downloading AzerothCore..."
            git clone --depth 1 \
                https://github.com/azerothcore/acore-docker.git \
                "$SERVER_DIR"

            if [ ! -f "$SERVER_DIR/docker-compose.yml" ]; then
                print_error "Download failed. Check your internet connection."
                exit 1
            fi

            # Fix phpMyAdmin port conflict
            cat > "$SERVER_DIR/docker-compose.override.yml" << 'EOF'
services:
  phpmyadmin:
    ports:
      - "8181:80"
EOF

            mkdir -p "$SERVER_DIR/scripts/lua"
            print_success "AzerothCore downloaded!"

            # Install modules
            install_modules_base

            # Pull images
            print_info "Downloading server images..."
            cd "$SERVER_DIR"
            if ! docker compose pull; then
                print_error "Failed to download server images."
                exit 1
            fi
            print_success "Images downloaded!"

            # Start server
            print_info "Starting server..."
            if ! docker compose up -d --scale phpmyadmin=0; then
                print_error "Failed to start server."
                exit 1
            fi
            ;;

        # ── NPCBOTS ───────────────────────────────
        npcbots)
            if [ "$BUILD_METHOD" = "prebuilt" ]; then
                print_info "Using pre-built NPCBots images..."
                print_info "Downloading AzerothCore NPCBots..."

                # Clone trickerer fork for SQL files and config
                git clone --depth 1 \
                    https://github.com/trickerer/AzerothCore-wotlk-with-NPCBots.git \
                    "$SERVER_DIR"

                # Save SQL files
                mkdir -p "$HOME/npcbots-sql"
                cp -r "$SERVER_DIR/data/sql/custom/db_auth" "$HOME/npcbots-sql/"
                cp -r "$SERVER_DIR/data/sql/custom/db_characters" "$HOME/npcbots-sql/"
                cp -r "$SERVER_DIR/data/sql/custom/db_world" "$HOME/npcbots-sql/"

                # Replace with standard acore-docker for pre-built images
                sudo rm -rf "$SERVER_DIR"
                git clone --depth 1 \
                    https://github.com/azerothcore/acore-docker.git \
                    "$SERVER_DIR"

                cat > "$SERVER_DIR/docker-compose.override.yml" << 'EOF'
services:
  phpmyadmin:
    ports:
      - "8181:80"
EOF

                # Pull and start
                cd "$SERVER_DIR"
                docker compose pull
                docker compose up -d --scale phpmyadmin=0

            else
                # Compile from source
                print_info "Cloning NPCBots source (this is a big download)..."
                git clone --depth 1 \
                    https://github.com/trickerer/AzerothCore-wotlk-with-NPCBots.git \
                    "$SERVER_DIR"

                print_info "Compiling NPCBots server (2-4 hours)..."
                print_info "Progress saved to: ~/npcbots-build.log"
                cd "$SERVER_DIR"
                docker compose up -d --build 2>&1 | tee ~/npcbots-build.log

                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                    print_error "Compilation failed. Check ~/npcbots-build.log"
                    exit 1
                fi
            fi

            print_success "NPCBots server installed!"
            install_modules_npcbots
            ;;

        # ── PLAYERBOTS ────────────────────────────
        playerbots)
            print_info "Cloning Playerbots source..."
            print_warning "This will take 2-4 hours to compile!"
            print_info "Keep your Steam Deck plugged in!"

            git clone --depth 1 \
                https://github.com/liyunfan1223/azerothcore-wotlk.git \
                --branch Playerbot \
                "$SERVER_DIR"

            if [ ! -d "$SERVER_DIR" ]; then
                print_error "Clone failed. Check your internet connection."
                exit 1
            fi

            # Clone mod-playerbots into modules
            mkdir -p "$SERVER_DIR/modules"
            git clone --depth 1 \
                https://github.com/liyunfan1223/mod-playerbots.git \
                "$SERVER_DIR/modules/mod-playerbots"

            print_info "Compiling Playerbots server (2-4 hours)..."
            print_info "Progress saved to: ~/playerbots-build.log"

            cd "$SERVER_DIR"

            # Create docker-compose for playerbots if needed
            if [ ! -f "docker-compose.yml" ]; then
                print_error "No docker-compose.yml found in Playerbots repo."
                print_info "Check the repo structure manually."
                exit 1
            fi

            docker compose up -d --build 2>&1 | tee ~/playerbots-build.log

            if [ ${PIPESTATUS[0]} -ne 0 ]; then
                print_error "Compilation failed. Check ~/playerbots-build.log"
                exit 1
            fi

            print_success "Playerbots server compiled!"
            install_modules_playerbots
            ;;
    esac
}

# ─────────────────────────────────────────
# MODULE INSTALLERS
# ─────────────────────────────────────────
install_modules_base() {
    local modules_dir="$SERVER_DIR/modules"
    mkdir -p "$modules_dir"

    if [ "$MOD_AHBOT" = true ]; then
        print_info "Installing AH Bot..."
        git clone --depth 1 \
            https://github.com/azerothcore/mod-ah-bot.git \
            "$modules_dir/mod-ah-bot" 2>/dev/null && \
            print_success "AH Bot installed!" || \
            print_warning "AH Bot install failed — add manually later"
    fi

    if [ "$MOD_PROGRESSION" = true ]; then
        print_info "Installing Individual Progression..."
        git clone --depth 1 \
            https://github.com/ZhengPeiRu21/mod-individual-progression.git \
            "$modules_dir/mod-individual-progression" 2>/dev/null && \
            print_success "Individual Progression installed!" || \
            print_warning "Individual Progression failed — add manually later"
    fi

    if [ "$MOD_DUNGEON_MASTER" = true ]; then
        print_info "Installing Dungeon Master..."
        git clone --depth 1 \
            https://github.com/InstanceForge/mod-dungeon-master.git \
            "$modules_dir/mod-dungeon-master" 2>/dev/null && \
            print_success "Dungeon Master installed!" || \
            print_warning "Dungeon Master failed — add manually later"
    fi

    if [ "$MOD_SOLOCRAFT" = true ]; then
        print_info "Installing Solocraft..."
        git clone --depth 1 \
            https://github.com/azerothcore/mod-solocraft.git \
            "$modules_dir/mod-solocraft" 2>/dev/null && \
            print_success "Solocraft installed!" || \
            print_warning "Solocraft failed — add manually later"
    fi
}

install_modules_npcbots() {
    # Apply NPCBots SQL if we have them
    if [ -d "$HOME/npcbots-sql" ] && [ "$BUILD_METHOD" = "prebuilt" ]; then
        print_info "Waiting for database to be ready..."
        sleep 15

        DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i "database" | head -1)
        DB_CONTAINER="${DB_CONTAINER:-wow-server-ac-database-1}"

        print_info "Applying NPCBots database files..."
        for f in "$HOME/npcbots-sql/db_auth/"*.sql; do
            docker exec -i "$DB_CONTAINER" mysql -uroot -ppassword acore_auth < "$f" 2>/dev/null || true
        done
        for f in "$HOME/npcbots-sql/db_characters/"*.sql; do
            docker exec -i "$DB_CONTAINER" mysql -uroot -ppassword acore_characters < "$f" 2>/dev/null || true
        done
        for f in "$HOME/npcbots-sql/db_world/"*.sql; do
            docker exec -i "$DB_CONTAINER" mysql -uroot -ppassword acore_world < "$f" 2>/dev/null || true
        done
        print_success "NPCBots database applied!"
    fi

    # Apply other modules as SQL where possible
    if [ "$MOD_AHBOT" = true ]; then
        print_info "AH Bot module noted — configure via worldserver.conf"
    fi
}

install_modules_playerbots() {
    print_info "Playerbots modules configured during compilation"
    if [ "$MOD_AHBOT" = true ]; then
        print_info "AH Bot: configure via worldserver.conf after server starts"
    fi
}

# ─────────────────────────────────────────
# WAIT FOR SERVER READY
# ─────────────────────────────────────────
wait_for_server() {
    print_info "Waiting for world server to initialize..."

    if [ "$BUILD_METHOD" = "compile" ]; then
        print_info "First launch after compilation may take 10-15 minutes."
    else
        print_info "First launch: 5-15 minutes. After first launch: ~30 seconds."
    fi

    echo ""

    TIMEOUT=1800
    ELAPSED=0
    READY=0
    WORLD_CONTAINER=""

    while [ $ELAPSED -lt $TIMEOUT ]; do
        WORLD_CONTAINER=$(docker ps --format '{{.Names}}' \
            2>/dev/null | grep -i "worldserver" | head -1)

        if [ -n "$WORLD_CONTAINER" ]; then
            if docker logs "$WORLD_CONTAINER" \
                2>/dev/null | grep -q "ready\.\.\."; then
                READY=1
                break
            fi
        fi

        printf "."
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done

    echo ""
    echo ""

    if [ $READY -eq 1 ]; then
        print_success "Server is READY! ⚔️"
    else
        print_warning "Server is taking longer than expected."
        print_info "Check progress: docker logs -f $WORLD_CONTAINER"
        print_info "Wait for 'ready...' then create accounts manually."
    fi
}

# ─────────────────────────────────────────
# STEP 5 — CREATE ACCOUNTS
# ─────────────────────────────────────────
create_accounts() {
    print_header
    print_step "STEP 5/6 — Create Your Accounts"

    # Detect containers
    DB_CONTAINER=$(docker ps --format '{{.Names}}' \
        2>/dev/null | grep -iE "ac.database|ac_database" | head -1)
    DB_CONTAINER="${DB_CONTAINER:-wow-server-ac-database-1}"

    WORLD_CONTAINER=$(docker ps --format '{{.Names}}' \
        2>/dev/null | grep -i "worldserver" | head -1)
    WORLD_CONTAINER="${WORLD_CONTAINER:-acore-docker-ac-worldserver-1}"

    # Wait for DB
    sleep 10

    # Always create admin account first
    print_info "Creating default admin account..."
    ADMIN_HASH=$(echo -n "ADMIN:ADMIN" | sha1sum 2>/dev/null | awk '{print toupper($1)}' || \
                 echo -n "ADMIN:ADMIN" | shasum -a 1 2>/dev/null | awk '{print toupper($1)}' || echo "")

    if [ -n "$ADMIN_HASH" ]; then
        docker exec "$DB_CONTAINER" mysql -uroot -ppassword acore_auth -e "
            INSERT INTO account (username, sha_pass_hash, reg_mail, email, joindate)
            VALUES ('ADMIN', '${ADMIN_HASH}', 'admin@local.lan', 'admin@local.lan', NOW())
            ON DUPLICATE KEY UPDATE sha_pass_hash='${ADMIN_HASH}';
        " 2>/dev/null || true

        ADMIN_ID=$(docker exec "$DB_CONTAINER" mysql -uroot -ppassword acore_auth -sNe \
            "SELECT id FROM account WHERE username='ADMIN';" 2>/dev/null)

        if [ -n "$ADMIN_ID" ]; then
            docker exec "$DB_CONTAINER" mysql -uroot -ppassword acore_auth -e "
                INSERT INTO account_access (id, gmlevel, RealmID)
                VALUES ('${ADMIN_ID}', 3, -1)
                ON DUPLICATE KEY UPDATE gmlevel=3;
            " 2>/dev/null || true
        fi
        print_success "Default account created!"
        print_info "  Username: admin  |  Password: admin  |  GM Level: 3"
    fi

    echo ""

    # Account creation loop
    while true; do
        if ! ask_yes_no "Create an additional account?"; then
            break
        fi

        echo ""
        while true; do
            echo -e "${WHITE}Username: ${NC}"
            read -r NEW_USERNAME
            [ -n "$NEW_USERNAME" ] && break
            echo "Username cannot be empty."
        done

        while true; do
            echo -e "${WHITE}Password: ${NC}"
            read -rs NEW_PASSWORD
            echo ""
            [ -n "$NEW_PASSWORD" ] && break
            echo "Password cannot be empty."
        done

        # Hash and create
        NEW_USER_UPPER=$(echo "$NEW_USERNAME" | tr '[:lower:]' '[:upper:]')
        NEW_PASS_UPPER=$(echo "$NEW_PASSWORD" | tr '[:lower:]' '[:upper:]')

        NEW_HASH=$(echo -n "${NEW_USER_UPPER}:${NEW_PASS_UPPER}" | sha1sum 2>/dev/null | awk '{print toupper($1)}' || \
                   echo -n "${NEW_USER_UPPER}:${NEW_PASS_UPPER}" | shasum -a 1 2>/dev/null | awk '{print toupper($1)}' || echo "")

        if [ -n "$NEW_HASH" ]; then
            docker exec "$DB_CONTAINER" mysql -uroot -ppassword acore_auth -e "
                INSERT INTO account (username, sha_pass_hash, reg_mail, email, joindate)
                VALUES (UPPER('${NEW_USERNAME}'), '${NEW_HASH}', 'admin@local.lan', 'admin@local.lan', NOW())
                ON DUPLICATE KEY UPDATE sha_pass_hash='${NEW_HASH}';
            " 2>/dev/null || true

            NEW_ID=$(docker exec "$DB_CONTAINER" mysql -uroot -ppassword acore_auth -sNe \
                "SELECT id FROM account WHERE username=UPPER('${NEW_USERNAME}');" 2>/dev/null)

            if [ -n "$NEW_ID" ]; then
                docker exec "$DB_CONTAINER" mysql -uroot -ppassword acore_auth -e "
                    INSERT INTO account_access (id, gmlevel, RealmID)
                    VALUES ('${NEW_ID}', 3, -1)
                    ON DUPLICATE KEY UPDATE gmlevel=3;
                " 2>/dev/null || true
                print_success "Account created: ${NEW_USERNAME} (GM Level 3)"
            else
                print_warning "Could not create ${NEW_USERNAME} automatically."
                print_info "Create it manually: docker attach $WORLD_CONTAINER"
                print_info "  account create ${NEW_USERNAME} ${NEW_PASSWORD} ${NEW_PASSWORD}"
                print_info "  account set gmlevel ${NEW_USERNAME} 3 -1"
            fi
        fi

        echo ""
    done
}

# ─────────────────────────────────────────
# STEP 6 — GAMING MODE SETUP
# ─────────────────────────────────────────
setup_gaming_mode() {
    print_step "STEP 6/6 — Setting Up Gaming Mode"

    local launcher_name="wow-gaming-mode.sh"
    [ "$SERVER_TYPE" = "npcbots" ]    && launcher_name="wow-npcbots-launcher.sh"
    [ "$SERVER_TYPE" = "playerbots" ] && launcher_name="wow-playerbots-launcher.sh"

    local launcher_path="$HOME/$launcher_name"
    local server_dir="$SERVER_DIR"

    cat > "$launcher_path" << LAUNCHER
#!/bin/bash
# Dad's MMO Lab — ${SERVER_NAME} Gaming Mode Launcher v${WIZARD_VERSION}
export PATH="/usr/bin:/usr/local/bin:/bin:\$PATH"
unset LD_PRELOAD
unset LD_LIBRARY_PATH

LOGFILE="/tmp/wow-launch.log"
exec 2>"\$LOGFILE"

clear
echo ""
echo "  ⚔️  DAD'S MMO LAB — ${SERVER_NAME}"
echo "  ══════════════════════════════════════"
echo ""
echo "  Starting server..."
echo ""

cd "${server_dir}" || exit 1
docker compose up -d --scale phpmyadmin=0 >> "\$LOGFILE" 2>&1

echo "  Containers started!"
echo ""
echo "  Waiting for world to initialize..."
echo "  First launch: 5-15 minutes"
echo "  After first launch: ~30 seconds"
echo ""

TIMEOUT=900
ELAPSED=0
READY=0
WORLD_CONTAINER=""

while [ \$ELAPSED -lt \$TIMEOUT ]; do
    WORLD_CONTAINER=\$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i "worldserver" | head -1)
    if [ -n "\$WORLD_CONTAINER" ]; then
        if docker logs "\$WORLD_CONTAINER" 2>/dev/null | grep -q "ready\.\.\."; then
            READY=1
            break
        fi
    fi
    printf "  ."
    sleep 5
    ELAPSED=\$((ELAPSED + 5))
done

echo ""
echo ""

if [ \$READY -eq 1 ]; then
    echo "  ══════════════════════════════════════"
    echo "  ✅ AZEROTH IS READY!"
    echo "  ══════════════════════════════════════"
else
    echo "  ⏳ Still initializing — launch WoW soon"
fi

echo ""
echo "  Press STEAM button and launch WoW"
echo "  Server AUTO-SHUTS DOWN when WoW closes"
echo ""

WOW_STARTED=0
for i in \$(seq 1 60); do
    if pgrep -f "Wow\.exe" > /dev/null 2>&1; then
        WOW_STARTED=1
        break
    fi
    sleep 5
done

if [ \$WOW_STARTED -eq 1 ]; then
    echo "  WoW detected! Enjoy Azeroth! ⚔️"
    while pgrep -f "Wow\.exe" > /dev/null 2>&1; do
        sleep 3
    done
    sleep 5
    echo "  WoW closed — shutting down..."
else
    echo "  WoW not detected — keeping server alive."
    sleep 10800
fi

cd "${server_dir}" && docker compose down >> "\$LOGFILE" 2>&1

echo ""
echo "  ✅ Server stopped! Safe to close."
echo "  Thanks for playing! youtube.com/@DadsMmoLab"
echo ""
sleep 5
LAUNCHER

    chmod +x "$launcher_path"
    print_success "Gaming Mode launcher created: ~/$launcher_name"

    # Save account info
    cat > "$SERVER_DIR/MY_ACCOUNTS.txt" << ACCOUNTS
====================================
  Dad's MMO Lab — ${SERVER_NAME}
  Your Server Accounts
====================================

DEFAULT ACCOUNT:
  Username: admin
  Password: admin
  GM Level: 3 (full admin)

Server: 127.0.0.1
Realmlist: set realmlist 127.0.0.1

====================================
  Gaming Mode Setup
====================================
Add to Steam:
  Target:  /usr/bin/konsole
  Options: --hold -e bash ~/${launcher_name}
  Proton:  OFF (do not enable)

====================================
  Useful Commands
====================================
Start:   cd ${server_dir} && docker compose up -d
Stop:    cd ${server_dir} && docker compose down
Console: docker attach \$(docker ps --format '{{.Names}}' | grep worldserver | head -1)
         (exit: Ctrl+P then Ctrl+Q)
====================================
ACCOUNTS

    print_success "Account info saved to: $SERVER_DIR/MY_ACCOUNTS.txt"
}

# ─────────────────────────────────────────
# DONE
# ─────────────────────────────────────────
show_completion() {
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   🎉 YOUR SERVER IS READY!                       ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}${BOLD}Server:${NC}  ${CYAN}$SERVER_NAME${NC}"
    echo -e "  ${WHITE}${BOLD}Folder:${NC}  ${CYAN}$SERVER_DIR${NC}"
    echo ""
    echo -e "  ${WHITE}${BOLD}ONE LAST THING — Set your WoW realmlist:${NC}"
    echo -e "  1. Find your WoW folder"
    echo -e "  2. Open ${CYAN}realmlist.wtf${NC}"
    echo -e "  3. Set it to: ${GREEN}set realmlist 127.0.0.1${NC}"
    echo -e "  4. Save and launch WoW!"
    echo ""
    echo -e "  ${WHITE}${BOLD}Gaming Mode:${NC}"
    echo -e "  Add to Steam → Target: ${CYAN}/usr/bin/konsole${NC}"

    local launcher_name="wow-gaming-mode.sh"
    [ "$SERVER_TYPE" = "npcbots" ]    && launcher_name="wow-npcbots-launcher.sh"
    [ "$SERVER_TYPE" = "playerbots" ] && launcher_name="wow-playerbots-launcher.sh"

    echo -e "  Launch Options: ${CYAN}--hold -e bash ~/${launcher_name}${NC}"
    echo -e "  Proton: ${RED}OFF${NC}"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  📺 youtube.com/@DadsMmoLab${NC}"
    echo -e "${WHITE}  📦 github.com/DadsMmoLab/dads-mmo-lab${NC}"
    echo -e "${WHITE}  ☕ ko-fi.com/dadsmmolab${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}${BOLD}Welcome to Azeroth. It's yours now. Forever. ⚔️${NC}"
    echo ""
}

# ─────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────
print_header

echo -e "${WHITE}Welcome to the WoW Server Setup Wizard!${NC}"
echo -e "${WHITE}We'll guide you through building your perfect${NC}"
echo -e "${WHITE}offline WoW experience step by step.${NC}"
echo ""
echo -e "${BLUE}This takes about 5 minutes to configure${NC}"
echo -e "${BLUE}then sits back and installs itself.${NC}"
echo ""

if ! ask_yes_no "Ready to begin?"; then
    echo "No problem — run this script when you're ready!"
    exit 0
fi

check_system
choose_server_type
choose_modules
show_summary
install_server
wait_for_server
create_accounts
setup_gaming_mode
show_completion
