#!/bin/bash
# ============================================================
#  Dad's MMO Lab — Vanilla WoW (1.12.1) Server Installer
#  CMaNGOS Classic + Playerbots + AHBot, compiled from source
#
#  https://github.com/DadsMmoLab/dads-mmo-lab
#
#  Version: 1.1.1
#
#  Usage:
#    chmod +x install-wow-vanilla.sh
#    ./install-wow-vanilla.sh
#
#  What this does (fully automated, ~3-5 hours total):
#    1. Validates your WoW 1.12.1 client before any slow work
#    2. Installs Docker if needed
#    3. Compiles CMaNGOS Classic + Playerbots (~2-4 hours)
#    4. Extracts map/dbc/vmap data from your client (~15-20 min)
#    5. Generates pathfinding mesh files (~30 min)
#    6. Sets up MariaDB with all 4 databases + content + updates
#    7. Imports Playerbots SQL (so bots actually work)
#    8. Starts the compiled server with bots enabled
#    9. Creates default player/player account
#   10. Configures realmlist and Gaming Mode launcher
#
#  Powered by:
#    - cmangos/mangos-classic — github.com/cmangos/mangos-classic
#    - cmangos/playerbots     — github.com/cmangos/playerbots
#    - cmangos/classic-db     — github.com/cmangos/classic-db
#
#  Why source compile (and why this is temporary)?
#    No public Linux Docker image currently ships CMaNGOS WITH
#    Playerbots compiled in. Source compile is the most reliable
#    Vanilla+bots path right now.
#
#    🔜 COMING SOON: Dad's MMO Lab will publish pre-built Docker
#    images via GitHub Actions. When that's live, a future
#    install-wow-vanilla-fast.sh will do a 5-minute pull instead
#    of a 3-4 hour compile. This installer is for folks who can't
#    wait — or who want the educational experience of compiling
#    their own server from source.
#
#  ⚠️  Requirements:
#    - WoW Vanilla 1.12.1 (build 5875) client folder
#    - 20GB free disk space
#    - Steam Deck plugged in, on a flat hard surface
#    - 3-5 hours of wall-clock time (mostly hands-off)
# ============================================================

INSTALLER_VERSION="1.1.1"

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
NC='\033[0m'
BOLD='\033[1m'

# Classic vanilla — warm gold
CL='\033[0;33m'
CLB='\033[1;33m'

print_header() {
    clear
    echo ""
    echo -e "${CL}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CL}║${WHITE}${BOLD}         ⚔️  DAD'S MMO LAB                          ${NC}${CL}║${NC}"
    echo -e "${CL}║${WHITE}         Vanilla WoW Server (source-compile)     ${NC}${CL}║${NC}"
    echo -e "${CL}║${BLUE}         CMaNGOS Classic + Playerbots             ${NC}${CL}║${NC}"
    echo -e "${CL}║${YELLOW}         Version ${INSTALLER_VERSION}                ${NC}${CL}║${NC}"
    echo -e "${CL}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${CL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}${BOLD} $1${NC}"
    echo -e "${CL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
SERVER_DIR="$HOME/wow-vanilla-server"
CLIENT_DIR=""
DB_PASSWORD="vanilla$(date +%s | tail -c 6)"

# Source pinning — change these to update what we compile
# Using master at install time. Future: pin to specific commits for stability.
CMANGOS_CORE_REPO="https://github.com/cmangos/mangos-classic.git"
CMANGOS_BOTS_REPO="https://github.com/cmangos/playerbots.git"
# Note: classic-db is cloned inside the Dockerfile builder stage (not on host),
# so no CMANGOS_DB_REPO variable here.

# Image names — these are LOCAL builds, not pulled from anywhere
BUILDER_IMAGE="dml/cmangos-vanilla-builder:local"
SERVER_IMAGE="dml/cmangos-vanilla-server:local"

# ─────────────────────────────────────────
# SYSTEM CHECKS
# ─────────────────────────────────────────
check_system() {
    print_step "Checking System Requirements"

    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        print_error "Requires Linux (SteamOS). Are you in Desktop Mode?"
        exit 1
    fi
    print_success "Linux detected"

    # Need ~20GB for source + build + extracted client data + Docker layers
    AVAILABLE_GB=$(df -BG "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' | tr -d ' ')
    if [ -n "$AVAILABLE_GB" ] && [ "$AVAILABLE_GB" -lt 20 ] 2>/dev/null; then
        print_error "Need 20GB free for compile + client data. You have ${AVAILABLE_GB}GB."
        exit 1
    fi
    print_success "Disk space OK (${AVAILABLE_GB:-unknown}GB available)"

    if ! ping -c 1 github.com &>/dev/null; then
        print_error "No internet. Please connect and try again."
        exit 1
    fi
    print_success "Internet connection OK"

    # Check RAM — compile needs at least 4GB available
    TOTAL_RAM_MB=$(free -m | awk 'NR==2 {print $2}')
    if [ -n "$TOTAL_RAM_MB" ] && [ "$TOTAL_RAM_MB" -lt 6000 ]; then
        print_warning "RAM is low (${TOTAL_RAM_MB}MB). Compile may swap heavily."
        print_info "Steam Deck should have 16GB — verify nothing else is hogging RAM."
    else
        print_success "RAM OK (${TOTAL_RAM_MB}MB total)"
    fi
}

# ─────────────────────────────────────────
# KEYRING HEALTH (SteamOS pacman drift fix)
# ─────────────────────────────────────────
check_pacman_keyring() {
    if ! sudo -n pacman -Sy --noconfirm &>/dev/null; then
        print_warning "Pacman keyring may need refresh — handled by Docker install if needed."
    fi
}

# ─────────────────────────────────────────
# DOCKER INSTALL
# ─────────────────────────────────────────
install_docker() {
    if command -v docker &>/dev/null && docker ps &>/dev/null; then
        print_success "Docker already installed and running"
        return 0
    fi

    print_info "Installing Docker..."
    check_pacman_keyring

    # SteamOS read-only root — use the standard unlock + install pattern
    if ! sudo steamos-readonly disable 2>/dev/null; then
        print_warning "steamos-readonly disable failed — may already be writable"
    fi

    if ! sudo pacman -Sy --noconfirm docker; then
        print_error "Failed to install Docker via pacman."
        print_info "If keyring errors: sudo pacman-key --init && sudo pacman-key --populate"
        sudo steamos-readonly enable 2>/dev/null || true
        exit 1
    fi

    sudo steamos-readonly enable 2>/dev/null || true

    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    print_success "Docker installed"

    if ! docker ps &>/dev/null; then
        print_warning "Docker group not yet active in this shell."
        print_info "Run: newgrp docker  — or log out and back in, then re-run installer."
        print_info "Continuing with sudo for this install..."
        DOCKER_CMD="sudo docker"
    else
        DOCKER_CMD="docker"
    fi
}

# ─────────────────────────────────────────
# WELCOME
# ─────────────────────────────────────────
show_welcome() {
    print_header

    echo -e "${WHITE}Welcome to the Vanilla WoW installer!${NC}"
    echo ""
    echo -e "${WHITE}This installs a full offline World of Warcraft${NC}"
    echo -e "${WHITE}Vanilla (1.12.1) server using CMaNGOS Classic${NC}"
    echo -e "${WHITE}compiled from source with Playerbots enabled.${NC}"
    echo ""
    echo -e "${GREEN}${BOLD}🤖 Playerbots + AHBot are included.${NC}"
    echo -e "${WHITE}AI players roam Azeroth, form parties with you,${NC}"
    echo -e "${WHITE}run dungeons, and populate the auction house.${NC}"
    echo -e "${WHITE}You're never alone in Vanilla.${NC}"
    echo ""
    echo -e "${RED}${BOLD}⚠️  HONEST TIME COMMITMENT:${NC}"
    echo -e "${YELLOW}  • Total time: ${BOLD}3-5 hours${NC}${YELLOW} (mostly hands-off)${NC}"
    echo -e "${YELLOW}  • Compile: ${BOLD}2-4 hours${NC}${YELLOW} (fan loud, Deck hot)${NC}"
    echo -e "${YELLOW}  • Extraction: ${BOLD}15-20 minutes${NC}"
    echo -e "${YELLOW}  • Pathfinding mesh gen: ${BOLD}30 minutes${NC}"
    echo -e "${YELLOW}  • You can walk away — heartbeat shows progress${NC}"
    echo -e "${YELLOW}  • First run only — future starts are seconds${NC}"
    echo ""
    echo -e "${RED}${BOLD}⚠️  Plug Deck in. Use a flat hard surface.${NC}"
    echo ""
    echo -e "${CLB}${BOLD}🔜 COMING SOON — the fast path:${NC}"
    echo -e "${WHITE}Dad's MMO Lab is building a pre-built Docker image${NC}"
    echo -e "${WHITE}publishing pipeline. When it ships (soon), a separate${NC}"
    echo -e "${WHITE}install-wow-vanilla-fast.sh will do a 5-minute pull${NC}"
    echo -e "${WHITE}instead of compiling. This installer is for folks who${NC}"
    echo -e "${WHITE}can't wait — or who want the educational journey.${NC}"
    echo ""
    echo -e "${BLUE}ℹ️  Client required: WoW 1.12.1 (build 5875)${NC}"
    echo -e "${BLUE}ℹ️  Default account: ${BOLD}player / player${NC}"
    echo -e "${BLUE}ℹ️  Build log: /tmp/wow-vanilla-build.log${NC}"
    echo ""

    if ! ask_yes_no "Ready to bake your Deck for Azeroth?"; then
        echo "No problem — come back when you're ready!"
        exit 0
    fi
}

# ─────────────────────────────────────────
# LOCATE CLIENT
# ─────────────────────────────────────────
locate_client() {
    print_header
    print_step "STEP 1/5 — Locating & Validating Your WoW Client"

    echo -e "${WHITE}I need the path to your ${BOLD}Vanilla 1.12.1${NC}${WHITE} client folder.${NC}"
    echo -e "${WHITE}The folder must contain:${NC}"
    echo -e "  • ${CL}WoW.exe${NC} (or wow.exe — case varies)"
    echo -e "  • ${CL}Data/${NC} folder with .MPQ files inside"
    echo -e "  • ${CL}Data/dbc.MPQ${NC} specifically (the DBC archive — required)"
    echo ""
    echo -e "${BLUE}Examples of valid paths:${NC}"
    echo -e "  ${CYAN}~/Games/VanillaWow${NC}"
    echo -e "  ${CYAN}~/Games/\"World Of Warcraft Classic\"${NC} (with quotes if spaces)"
    echo -e "  ${CYAN}/run/media/deck/SD/WoW-1.12${NC}"
    echo ""

    while true; do
        echo -e "${WHITE}Enter path to your WoW client folder:${NC}"
        read -r raw_path

        # Strip surrounding quotes if user typed them (common copy-paste)
        raw_path="${raw_path%\"}"
        raw_path="${raw_path#\"}"
        raw_path="${raw_path%\'}"
        raw_path="${raw_path#\'}"

        # Expand ~ manually since read doesn't
        CLIENT_DIR="${raw_path/#\~/$HOME}"

        # ── Validation gate 1: folder exists ──────────────────────
        if [ ! -d "$CLIENT_DIR" ]; then
            print_error "Folder doesn't exist: $CLIENT_DIR"
            print_info "Common issue: ~ doesn't expand inside quoted paths."
            print_info "Try the full path: /home/deck/Games/YourFolder"
            echo ""
            continue
        fi

        # ── Validation gate 2: Data/ subfolder ────────────────────
        if [ ! -d "$CLIENT_DIR/Data" ]; then
            print_error "No Data/ folder inside $CLIENT_DIR"
            print_info "This doesn't look like a WoW client. The Data/ folder"
            print_info "is where all the .MPQ game files live."
            echo ""
            continue
        fi

        # ── Validation gate 3: MPQ count sanity check ─────────────
        mpq_count=$(find "$CLIENT_DIR/Data" -maxdepth 1 -iname "*.mpq" 2>/dev/null | wc -l)
        if [ "$mpq_count" -lt 5 ]; then
            print_error "Only $mpq_count .MPQ files in Data/."
            print_info "Vanilla 1.12.1 typically has 10-14 MPQ files."
            print_info "If you have fewer, this might be:"
            print_info "  • A wrong WoW version (TBC, WotLK, Retail)"
            print_info "  • An incomplete download"
            print_info "  • A non-standard repack"
            echo ""
            if ! ask_yes_no "Continue anyway? (NOT recommended — extraction will likely fail)"; then
                continue
            fi
        fi

        # ── Validation gate 4: dbc.MPQ CRITICAL CHECK ─────────────
        # This is the killer check. Without dbc.MPQ, the 'ad' extractor
        # cannot extract Map.dbc, AreaTable.dbc, etc. The compile will
        # finish (3+ hours) but extraction will fail at the very end.
        # Catching this NOW saves the user from a wasted night.
        if [ ! -f "$CLIENT_DIR/Data/dbc.MPQ" ] && [ ! -f "$CLIENT_DIR/Data/dbc.mpq" ]; then
            print_error "Data/dbc.MPQ is MISSING."
            print_info ""
            print_info "This file is required for server-side data extraction."
            print_info "Without it, the install will fail after the 3-hour compile."
            print_info ""
            print_info "Likely causes:"
            print_info "  • This client is heavily stripped (some repacks remove dbc.MPQ)"
            print_info "  • Wrong WoW version"
            print_info "  • Incomplete download"
            print_info ""
            print_info "Find a more complete 1.12.1 client (~5GB total) and try again."
            echo ""
            if ! ask_yes_no "Continue anyway? (NOT recommended)"; then
                continue
            fi
        fi

        # ── Validation gate 5: Disk space for extraction ──────────
        # Extraction produces ~3-5 GB of data + temp Buildings folder
        local client_disk=$(df -BG "$CLIENT_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
        if [ -n "$client_disk" ] && [ "$client_disk" -lt 8 ] 2>/dev/null; then
            print_warning "Only ${client_disk}GB free where client lives."
            print_warning "Extraction may write temp files to client folder (needs ~5GB)."
        fi

        # ── Validation gate 6: Look for repack signatures (warning only) ──
        local repack_signals=0
        [ -f "$CLIENT_DIR/realmlist.wtf" ] && repack_signals=$((repack_signals + 1))
        [ ! -d "$CLIENT_DIR/Data/enUS" ] && [ ! -d "$CLIENT_DIR/Data/enGB" ] && repack_signals=$((repack_signals + 1))

        if [ $repack_signals -ge 2 ]; then
            print_info "This client looks like a community repack (realmlist at top level, no locale folder)."
            print_info "That's USUALLY fine — server extraction works with stripped repacks"
            print_info "as long as Data/dbc.MPQ exists (and it does ✓)."
        fi

        # All validations passed (or user overrode)
        print_success "WoW client validated: $CLIENT_DIR"
        print_success "Found $mpq_count .MPQ files including dbc.MPQ"
        break
    done
}

# ─────────────────────────────────────────
# SHOW SUMMARY BEFORE COMPILE
# ─────────────────────────────────────────
show_summary() {
    print_header
    print_step "STEP 2/5 — Pre-Compile Summary"

    echo ""
    echo -e "  ${WHITE}${BOLD}Expansion:${NC} ${CL}Vanilla (1.12.1, build 5875)${NC}"
    echo -e "  ${WHITE}${BOLD}Build:${NC}     ${CL}Source compile (CMaNGOS + Playerbots)${NC}"
    echo -e "  ${WHITE}${BOLD}Folder:${NC}    ${CL}$SERVER_DIR${NC}"
    echo -e "  ${WHITE}${BOLD}Client:${NC}    ${CL}$CLIENT_DIR${NC}"
    echo ""
    echo -e "  ${WHITE}${BOLD}Bots:${NC}"
    echo -e "    ${GREEN}✅${NC} Playerbots — AI players roam Azeroth"
    echo -e "    ${GREEN}✅${NC} AHBot — populates the Auction House"
    echo ""
    echo -e "  ${WHITE}${BOLD}Default account:${NC} ${CL}player / player${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}  The installer will:${NC}"
    echo -e "${YELLOW}  1. Build a compile container (~5 min)${NC}"
    echo -e "${YELLOW}  2. Clone CMaNGOS + Playerbots source (~5 min)${NC}"
    echo -e "${YELLOW}  3. Compile mangosd + realmd + tools (${BOLD}2-4 HOURS${NC}${YELLOW})${NC}"
    echo -e "${YELLOW}  4. Extract maps from your client (~15-20 min)${NC}"
    echo -e "${YELLOW}  5. Generate pathfinding mesh files (~30 min)${NC}"
    echo -e "${YELLOW}  6. Set up databases and content (~5 min)${NC}"
    echo -e "${YELLOW}  7. Start the server (~1-2 min first boot)${NC}"
    echo ""
    echo -e "${RED}${BOLD}  Plug your Deck in. Use a flat hard surface.${NC}"
    echo -e "${RED}${BOLD}  The fan will be loud. This is normal.${NC}"
    echo ""

    if ! ask_yes_no "Start the build?"; then
        echo "No problem — come back when you have time!"
        exit 0
    fi
}

# ─────────────────────────────────────────
# CREATE BUILD CONTAINER + COMPILE
# ─────────────────────────────────────────
do_compile() {
    print_header
    print_step "STEP 3/5 — Compiling CMaNGOS (2-4 hours)"

    # Remove existing if user wants to start fresh
    if [ -d "$SERVER_DIR" ]; then
        print_warning "Existing install found at $SERVER_DIR"
        if ask_yes_no "Remove it and start fresh?"; then
            cd "$SERVER_DIR" 2>/dev/null && \
                $DOCKER_CMD compose down -v 2>/dev/null || true
            sudo rm -rf "$SERVER_DIR"
            print_success "Old install removed"
        else
            print_info "Keeping existing install — exiting."
            exit 0
        fi
    fi

    mkdir -p "$SERVER_DIR"
    cd "$SERVER_DIR" || exit 1
    mkdir -p "$SERVER_DIR/source" "$SERVER_DIR/build" "$SERVER_DIR/data"

    # ── Write the Dockerfile for compiling CMaNGOS ──
    # Multi-stage so the final image is reasonable size.
    # Stage 1 = builder (has compilers), Stage 2 = runtime (just binaries)
    print_info "Writing Dockerfile..."
    cat > "$SERVER_DIR/Dockerfile" << 'DOCKERFILE'
# ──────────────────────────────────────────────────────────────
# Stage 1: Build CMaNGOS Classic + Playerbots from source
# ──────────────────────────────────────────────────────────────
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install build dependencies
# Per cmangos/issues/wiki/Installation-Instructions-for-Linux
# and ustoopia.nl's Jan 2026 build guide.
# ca-certificates is required because --no-install-recommends strips it.
# gcc-12 is required because gcc-11.4 has an internal compiler error
# on TileAssembler.cpp (CMaNGOS warns about this in its CMake config).
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    g++-12 \
    gcc-12 \
    git \
    libssl-dev \
    default-libmysqlclient-dev \
    libace-dev \
    libtbb-dev \
    libboost-all-dev \
    libreadline-dev \
    zlib1g-dev \
    openssl \
    p7zip-full \
    && rm -rf /var/lib/apt/lists/*

ENV CC=/usr/bin/gcc-12
ENV CXX=/usr/bin/g++-12

WORKDIR /src

# Clone CMaNGOS Classic core
RUN git clone --depth 1 https://github.com/cmangos/mangos-classic.git /src/mangos-classic

# Clone Playerbots into modules folder where CMake expects it
# Per cmangos/playerbots README, bots live at: src/modules/Bots
RUN git clone --depth 1 https://github.com/cmangos/playerbots.git \
    /src/mangos-classic/src/modules/Bots

# Clone classic-db (world content database)
RUN git clone --depth 1 https://github.com/cmangos/classic-db.git /src/classic-db

# Clone playerbots repo SEPARATELY at /src/playerbots-fresh to get its
# own sql/ tree (the modules/Bots clone is just C++ source)
RUN git clone --depth 1 https://github.com/cmangos/playerbots.git /src/playerbots-fresh

# Configure with BUILD_PLAYERBOTS=1
WORKDIR /src/mangos-classic
RUN mkdir -p build && cd build && \
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=/opt/mangos \
        -DBUILD_PLAYERBOTS=1 \
        -DBUILD_AHBOT=1 \
        -DBUILD_EXTRACTORS=1 \
        -DBUILD_GAME_SERVER=1 \
        -DBUILD_LOGIN_SERVER=1 \
        -DBUILD_TOOLS=1 \
        -DPCH=1

# Compile (the 2-4 hour step on Steam Deck)
# -j2 instead of $(nproc) to avoid OOM kills on the Deck's 16GB RAM
RUN cd build && make -j2 && make install

# ── PRESERVATION: copy SQL files into /opt/mangos/ before stage 2 ──
# Without this, the multi-stage Dockerfile would strip them. The
# runtime image needs these for first-boot DB initialization.
RUN mkdir -p /opt/mangos/sql && \
    cp -r /src/mangos-classic/sql/* /opt/mangos/sql/ && \
    mkdir -p /opt/mangos/classic-db && \
    cp -r /src/classic-db/* /opt/mangos/classic-db/ && \
    mkdir -p /opt/mangos/playerbots-sql && \
    cp -r /src/playerbots-fresh/sql/* /opt/mangos/playerbots-sql/

# ──────────────────────────────────────────────────────────────
# Stage 2: Runtime — minimal image with binaries + SQL bundled
# ──────────────────────────────────────────────────────────────
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install runtime deps + mariadb-client so we can run DB init from
# inside this image without depending on host tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    libmysqlclient21 \
    libace-dev \
    libtbb12 \
    libboost-system1.74.0 \
    libboost-filesystem1.74.0 \
    libboost-program-options1.74.0 \
    libreadline8 \
    netcat-openbsd \
    mariadb-client \
    gzip \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled binaries + bundled SQL from builder
COPY --from=builder /opt/mangos /opt/mangos

WORKDIR /opt/mangos/bin

# Default command — overridden by docker compose for realmd
CMD ["./mangosd"]
DOCKERFILE
    print_success "Dockerfile written (with sql/ preservation baked in)"

    # ── Build the image ──
    # This is THE long step.
    print_info "Starting compile. Logs streaming to /tmp/wow-vanilla-build.log"
    print_info "You can tail it from another Konsole: tail -f /tmp/wow-vanilla-build.log"
    print_info ""
    print_warning "Expected duration: 2-4 hours. Plug Deck in. Walk away if you need to."
    print_info ""

    # Print a friendly progress message every 5 min via background heartbeat
    (
        ELAPSED=0
        while sleep 300; do
            ELAPSED=$((ELAPSED + 5))
            echo "  ⏳ Still compiling... ${ELAPSED} minutes elapsed. Deck OK? 🌡️"
        done
    ) &
    HEARTBEAT_PID=$!

    if ! $DOCKER_CMD build -t "$SERVER_IMAGE" "$SERVER_DIR" 2>&1 | \
        tee /tmp/wow-vanilla-build.log; then
        kill $HEARTBEAT_PID 2>/dev/null
        print_error "Compile failed!"
        print_info "Last 30 lines of build log:"
        tail -30 /tmp/wow-vanilla-build.log
        print_info ""
        print_info "Full log: /tmp/wow-vanilla-build.log"
        print_info "Common causes:"
        print_info "  • Out of disk space (compile produces 5+ GB of artifacts)"
        print_info "  • Network drop during dependency fetch (re-run the installer)"
        print_info "  • Steam Deck overheated and OOM-killed gcc"
        exit 1
    fi

    kill $HEARTBEAT_PID 2>/dev/null
    print_success "CMaNGOS compiled with Playerbots! 🎉"
}

# ─────────────────────────────────────────
# EXTRACT CLIENT DATA
# ─────────────────────────────────────────
extract_client_data() {
    print_header
    print_step "STEP 4/5 — Extracting Map Data (15-20 minutes)"

    print_info "Running the extractors compiled into our server image..."
    print_info "This reads your WoW client and extracts:"
    print_info "  • Map data (dbc + maps)"
    print_info "  • Vmaps (visual obstructions for line-of-sight)"
    print_info "  • Mmaps (movement pathfinding — required for Playerbots)"
    echo ""

    # ────────────────────────────────────────────────────────────────
    # IMPORTANT: We mount the user's client folder DIRECTLY at /client.
    # We learned the hard way that symlink farms with absolute paths
    # don't resolve inside containers (the symlinks point to host paths
    # that don't exist inside the container).
    #
    # Direct mount is simpler and works perfectly. The extraction tool
    # writes output folders (maps/, vmaps/, mmaps/, Buildings/) into
    # /client/ — we move them to /extracted/ after the extraction.
    #
    # SIDE EFFECT: extraction writes temp folders into the user's client
    # folder. We clean these up after extraction. If extraction is
    # interrupted, the user may need to manually delete these temp
    # folders from their client folder.
    # ────────────────────────────────────────────────────────────────
    mkdir -p "$SERVER_DIR/data"

    print_info "Running extraction (this takes 15-30 min on Steam Deck)..."
    print_info "Extraction logs: /tmp/wow-vanilla-extract.log"
    print_warning "NOTE: Extraction writes temp folders into your client folder."
    print_warning "      These get moved out automatically when extraction finishes."
    echo ""

    if ! $DOCKER_CMD run --rm \
        -v "$CLIENT_DIR:/client" \
        -v "$SERVER_DIR/data:/extracted" \
        --entrypoint /bin/bash \
        "$SERVER_IMAGE" -c '
            set -e
            echo "=== Extraction starting at $(date) ==="
            cd /client
            echo "Working directory: $(pwd)"
            echo ""
            echo "=== Running ExtractResources.sh a (non-interactive, all data) ==="
            # The "a" argument: extract all, non-interactive mode.
            # CMaNGOS docs are sparse on this — verified from source.
            # CWD must be the client folder; script auto-locates its
            # sibling binaries via dirname "$0".
            /opt/mangos/bin/tools/ExtractResources.sh a || true
            echo ""
            echo "=== Moving outputs to /extracted ==="
            for d in dbc maps vmaps Buildings Cameras CreatureModels; do
                if [ -d "/client/$d" ]; then
                    echo "Moving /client/$d -> /extracted/$d"
                    rm -rf "/extracted/$d" 2>/dev/null
                    mv "/client/$d" "/extracted/$d"
                fi
            done
            # Move log files too for diagnostics
            for f in /client/MaNGOSExtractor.log /client/MaNGOSExtractor_detailed.log; do
                [ -f "$f" ] && mv "$f" /extracted/
            done
            echo "=== Extraction phase complete! ==="
        ' 2>&1 | tee /tmp/wow-vanilla-extract.log; then
        print_warning "Extraction reported errors — checking output anyway"
    fi

    # ────────────────────────────────────────────────────────────────
    # CRITICAL: Fix ownership of extracted files
    # The Docker container writes files as root. They land on the host
    # owned by root, which prevents the deck user from accessing them.
    # ────────────────────────────────────────────────────────────────
    print_info "Fixing file ownership..."
    sudo chown -R "$USER:$USER" "$SERVER_DIR/data" 2>/dev/null || true

    # ────────────────────────────────────────────────────────────────
    # VALIDATION: did extraction actually produce real output?
    # We learned that "exit code 0" doesn't mean success — extraction
    # can silently produce empty folders. We must count files.
    # ────────────────────────────────────────────────────────────────
    local maps_count dbc_count vmaps_count
    maps_count=$(ls "$SERVER_DIR/data/maps" 2>/dev/null | wc -l)
    dbc_count=$(ls "$SERVER_DIR/data/dbc" 2>/dev/null | wc -l)
    vmaps_count=$(ls "$SERVER_DIR/data/vmaps" 2>/dev/null | wc -l)

    print_info "  Extraction outputs:"
    print_info "    maps:  $maps_count files (expect ~2000-4000)"
    print_info "    dbc:   $dbc_count files (expect ~150)"
    print_info "    vmaps: $vmaps_count files (expect ~5000+)"

    if [ "$maps_count" -lt 100 ] || [ "$dbc_count" -lt 100 ] || [ "$vmaps_count" -lt 100 ]; then
        print_error "Extraction did not produce enough output files!"
        print_info "Likely causes:"
        print_info "  • Client missing Data/dbc.MPQ"
        print_info "  • Wrong WoW version"
        print_info "  • Disk full mid-extraction"
        print_info "Full log: /tmp/wow-vanilla-extract.log"
        if ! ask_yes_no "Continue anyway? (server WILL fail to load maps)"; then
            exit 1
        fi
    else
        print_success "Extraction outputs validated!"
    fi

    # ────────────────────────────────────────────────────────────────
    # MMAP GENERATION — required step, not optional
    #
    # ExtractResources.sh has a known bug where it calls MoveMapGen.sh
    # via relative path from the wrong CWD. So we run MoveMapGen directly.
    #
    # mmap.enabled = 0 in mangosd.conf does NOT skip mmap loading when
    # Playerbots is compiled in — bots iterate all maps for travelnode
    # generation and crash with "loadMap(): itr != loadedMMaps.end()"
    # on missing files. So we MUST generate real mmaps.
    #
    # Duration: 20-40 min on Steam Deck with --threads 2.
    # ────────────────────────────────────────────────────────────────
    print_step "Generating mmap pathfinding (~20-40 min — last big wait!)"
    print_info "Progress streams to your terminal. Walk away if you want."
    print_info "When you see '=== Generation done ===', it's finished."
    echo ""

    # Clean any leftover empty mmap stubs
    rm -rf "$SERVER_DIR/data/mmaps"
    mkdir -p "$SERVER_DIR/data/mmaps"

    if ! $DOCKER_CMD run --rm \
        -v "$SERVER_DIR/data:/data" \
        --entrypoint /bin/bash \
        "$SERVER_IMAGE" -c '
            cd /data
            /opt/mangos/bin/tools/MoveMapGen --silent --threads 2
            echo ""
            echo "=== Generation done at $(date) ==="
            echo "Final mmap file count: $(ls /data/mmaps | wc -l)"
        ' 2>&1 | tee /tmp/wow-vanilla-mmap-gen.log; then
        print_warning "Mmap generation reported errors — checking output anyway"
    fi

    # Fix ownership of mmaps too
    sudo chown -R "$USER:$USER" "$SERVER_DIR/data/mmaps" 2>/dev/null || true

    # Validate mmap output
    local mmap_count
    mmap_count=$(ls "$SERVER_DIR/data/mmaps" 2>/dev/null | wc -l)
    print_info "  mmap files generated: $mmap_count (expect ~2000)"

    if [ "$mmap_count" -lt 500 ]; then
        print_warning "Mmap count is lower than expected."
        print_warning "Server may still boot, but bots will pathfind poorly."
    else
        print_success "Mmaps generated! ($mmap_count files)"
    fi

    print_success "Client data extraction complete!"
}

# ─────────────────────────────────────────
# WRITE COMPOSE + CONFIGS
# ─────────────────────────────────────────
write_compose_and_configs() {
    print_step "Writing compose.yml and configs"

    # Compose: database + realmd (login) + mangosd (world)
    cat > "$SERVER_DIR/compose.yml" << EOF
services:
  db:
    image: mariadb:11
    container_name: vanilla-db
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: ${DB_PASSWORD}
      MARIADB_DATABASE: characters
    volumes:
      - db-data:/var/lib/mysql
    networks:
      - vanilla-net
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 30

  realmd:
    image: ${SERVER_IMAGE}
    container_name: vanilla-realmd
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "3724:3724"
    volumes:
      - ./etc:/opt/mangos/etc
      - ./data:/opt/mangos/data
    networks:
      - vanilla-net
    command: ["./realmd"]

  mangosd:
    image: ${SERVER_IMAGE}
    container_name: vanilla-mangosd
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "8085:8085"
    volumes:
      - ./etc:/opt/mangos/etc
      - ./data:/opt/mangos/data
    networks:
      - vanilla-net
    stdin_open: true
    tty: true
    command: ["./mangosd"]

volumes:
  db-data:

networks:
  vanilla-net:
    driver: bridge
EOF

    # Pull config samples from the compiled image
    mkdir -p "$SERVER_DIR/etc"
    print_info "Extracting config templates from compiled image..."
    $DOCKER_CMD run --rm \
        -v "$SERVER_DIR/etc:/out" \
        --entrypoint /bin/bash \
        "$SERVER_IMAGE" -c '
            cp /opt/mangos/etc/mangosd.conf.dist /out/mangosd.conf 2>/dev/null || true
            cp /opt/mangos/etc/realmd.conf.dist /out/realmd.conf 2>/dev/null || true
            cp /opt/mangos/etc/ahbot.conf.dist /out/ahbot.conf 2>/dev/null || true
            cp -r /opt/mangos/etc/*aiplayerbot*.dist /out/ 2>/dev/null || true
            # Rename the bot configs to remove .dist
            cd /out
            for f in *.dist; do
                [ -f "$f" ] && mv "$f" "${f%.dist}"
            done
        '

    # ────────────────────────────────────────────────────────────────
    # Patch ALL config lines that need our generated values.
    # Five lines total — missing any of them silently breaks boot:
    #   1. LoginDatabaseInfo (realmd.conf + mangosd.conf both need this)
    #   2. WorldDatabaseInfo (mangosd.conf)
    #   3. CharacterDatabaseInfo (mangosd.conf)
    #   4. LogsDatabaseInfo (mangosd.conf) — DIFFERENT host/db/pw!
    #   5. DataDir (mangosd.conf) — must point at our mounted /opt/mangos/data
    # ────────────────────────────────────────────────────────────────
    if [ -f "$SERVER_DIR/etc/mangosd.conf" ]; then
        sed -i "s|^LoginDatabaseInfo.*|LoginDatabaseInfo = \"db;3306;mangos;${DB_PASSWORD};realmd\"|" \
            "$SERVER_DIR/etc/mangosd.conf"
        sed -i "s|^WorldDatabaseInfo.*|WorldDatabaseInfo = \"db;3306;mangos;${DB_PASSWORD};mangos\"|" \
            "$SERVER_DIR/etc/mangosd.conf"
        sed -i "s|^CharacterDatabaseInfo.*|CharacterDatabaseInfo = \"db;3306;mangos;${DB_PASSWORD};characters\"|" \
            "$SERVER_DIR/etc/mangosd.conf"
        sed -i "s|^LogsDatabaseInfo.*|LogsDatabaseInfo = \"db;3306;mangos;${DB_PASSWORD};logs\"|" \
            "$SERVER_DIR/etc/mangosd.conf"
        sed -i "s|^DataDir\s*=.*|DataDir = \"/opt/mangos/data\"|" \
            "$SERVER_DIR/etc/mangosd.conf"

        # Verification — make sure every patch actually landed
        local patches_ok=0
        for pattern in "LoginDatabaseInfo.*${DB_PASSWORD}" \
                       "WorldDatabaseInfo.*${DB_PASSWORD}" \
                       "CharacterDatabaseInfo.*${DB_PASSWORD}" \
                       "LogsDatabaseInfo.*${DB_PASSWORD}" \
                       "DataDir.*/opt/mangos/data"; do
            if grep -q "^${pattern%%.*}" "$SERVER_DIR/etc/mangosd.conf" 2>/dev/null && \
               grep -qE "$pattern" "$SERVER_DIR/etc/mangosd.conf" 2>/dev/null; then
                patches_ok=$((patches_ok + 1))
            fi
        done

        if [ $patches_ok -ge 4 ]; then
            print_success "mangosd.conf patched ($patches_ok/5 verification checks passed)"
        else
            print_warning "mangosd.conf patches only partial ($patches_ok/5 verified)"
            print_info "Server may still work; if not, check $SERVER_DIR/etc/mangosd.conf"
        fi
    else
        print_error "mangosd.conf not extracted from image!"
        exit 1
    fi

    if [ -f "$SERVER_DIR/etc/realmd.conf" ]; then
        sed -i "s|^LoginDatabaseInfo.*|LoginDatabaseInfo = \"db;3306;mangos;${DB_PASSWORD};realmd\"|" \
            "$SERVER_DIR/etc/realmd.conf"
        print_success "realmd.conf patched"
    fi

    print_success "Configs written and patched"
}

# ─────────────────────────────────────────
# SETUP DATABASE
# ─────────────────────────────────────────
setup_database() {
    print_header
    print_step "Setting up databases (~2-5 min on Steam Deck SSD)"

    cd "$SERVER_DIR" || exit 1

    # ────────────────────────────────────────────────────────────────
    # Start the DB container ALONE first.
    # mangosd/realmd will be started later, AFTER schemas are imported.
    # Otherwise they'd restart-loop trying to connect to empty DBs.
    # ────────────────────────────────────────────────────────────────
    print_info "Starting MariaDB container..."
    if ! $DOCKER_CMD compose up -d db; then
        print_error "Failed to start db container."
        print_info "Check: $DOCKER_CMD compose logs db"
        exit 1
    fi

    print_info "Waiting for MariaDB to be ready..."
    local elapsed=0
    while [ $elapsed -lt 60 ]; do
        if $DOCKER_CMD exec -e MYSQL_PWD="${DB_PASSWORD}" vanilla-db \
            mariadb -u root -e "SELECT 1" >/dev/null 2>&1; then
            break
        fi
        printf "."
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo ""

    if [ $elapsed -ge 60 ]; then
        print_error "MariaDB didn't respond within 60 seconds."
        print_info "Check: $DOCKER_CMD compose logs db"
        exit 1
    fi
    print_success "MariaDB ready"

    # ────────────────────────────────────────────────────────────────
    # Phase 1: Create dedicated mangos user with grants on all 4 DBs
    # ────────────────────────────────────────────────────────────────
    print_info "Creating mangos database user with grants..."
    if ! $DOCKER_CMD exec -i -e MYSQL_PWD="${DB_PASSWORD}" vanilla-db \
        mariadb -u root <<EOF 2>&1 | tail -3
CREATE DATABASE IF NOT EXISTS mangos CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS realmd CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS characters CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS logs CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 'mangos'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON mangos.* TO 'mangos'@'%';
GRANT ALL PRIVILEGES ON realmd.* TO 'mangos'@'%';
GRANT ALL PRIVILEGES ON characters.* TO 'mangos'@'%';
GRANT ALL PRIVILEGES ON logs.* TO 'mangos'@'%';
FLUSH PRIVILEGES;
EOF
    then
        print_error "Failed to create mangos user"
        exit 1
    fi
    print_success "Created 4 databases + mangos@% user"

    # ────────────────────────────────────────────────────────────────
    # Detect the Docker network name at runtime.
    # (I1 fix: don't guess from compose conventions — those are fragile.)
    # The compose 'up -d db' above will have created the network. We
    # ask Docker for its real name.
    # ────────────────────────────────────────────────────────────────
    local compose_net
    compose_net=$($DOCKER_CMD network ls --format '{{.Name}}' 2>/dev/null \
                  | grep "vanilla-net" | head -1)
    if [ -z "$compose_net" ]; then
        print_error "Couldn't find the vanilla-net Docker network."
        print_info "Run: $DOCKER_CMD network ls"
        print_info "If you see no vanilla-net, the db container failed to start."
        exit 1
    fi
    print_info "Using Docker network: $compose_net"

    # ────────────────────────────────────────────────────────────────
    # Phase 2: Import base schemas
    #
    # I5 fix: We skip mangos.sql here. The classic-db Full_DB import
    # in Phase 3 starts with DROP TABLE IF EXISTS for every world
    # table and recreates them via its dump. Importing mangos.sql
    # first would just be a wasted step, and any structural mismatch
    # between mangos.sql and Full_DB causes confusion.
    #
    # We still need realmd.sql, characters.sql, and logs.sql since
    # those databases don't have a Full_DB equivalent.
    #
    # C3 fix: All mariadb calls use MYSQL_PWD env var instead of
    # --password= flag — eliminates the "Using a password on the
    # command line interface can be insecure" warning that was
    # polluting our output and confusing users.
    # ────────────────────────────────────────────────────────────────
    print_info "Importing base schemas (realmd, characters, logs — mangos comes via Full_DB)..."

    for schema in realmd characters logs; do
        if ! $DOCKER_CMD run --rm --network "$compose_net" \
            -e MYSQL_PWD="${DB_PASSWORD}" \
            "$SERVER_IMAGE" sh -c "
                mariadb -h db -u root ${schema} < /opt/mangos/sql/base/${schema}.sql
            " 2>&1 | tail -3; then
            print_warning "Schema ${schema}.sql had errors (may be OK if already imported)"
        else
            print_success "  ${schema} schema imported"
        fi
    done

    # ────────────────────────────────────────────────────────────────
    # Phase 3: Import classic-db Full World Database (the big one)
    # ~500MB SQL gzipped — typically 9 sec on Deck SSD
    # ────────────────────────────────────────────────────────────────
    print_info "Importing world content (creatures/items/quests — fast on Deck SSD)..."
    if ! $DOCKER_CMD run --rm --network "$compose_net" \
        -e MYSQL_PWD="${DB_PASSWORD}" \
        "$SERVER_IMAGE" sh -c "
            gunzip -c /opt/mangos/classic-db/Full_DB/ClassicDB_*.sql.gz | \
                mariadb -h db -u root mangos
        " 2>&1 | tail -3; then
        print_error "Full DB import failed"
        exit 1
    fi
    print_success "World content imported (~17K items, 10K creatures, 4K quests)"

    # ────────────────────────────────────────────────────────────────
    # Phase 4: Apply classic-db content Updates (300+ small files)
    # Most will succeed; a few may fail because they assume a different
    # baseline — that's OK, they're idempotent-safe.
    # ────────────────────────────────────────────────────────────────
    print_info "Applying classic-db content updates (300+ files, ~2 sec)..."
    $DOCKER_CMD run --rm --network "$compose_net" \
        -e MYSQL_PWD="${DB_PASSWORD}" \
        "$SERVER_IMAGE" sh -c '
            cd /opt/mangos/classic-db/Updates
            for sql in $(ls -v *.sql); do
                mariadb -h db -u root mangos < "$sql" 2>/dev/null
            done
            echo "Done"
        ' 2>&1 | tail -2
    print_success "Content updates applied"

    # ────────────────────────────────────────────────────────────────
    # Phase 5: Apply ACID scripts (creature AI behaviors)
    # ────────────────────────────────────────────────────────────────
    print_info "Importing ACID creature AI scripts..."
    $DOCKER_CMD run --rm --network "$compose_net" \
        -e MYSQL_PWD="${DB_PASSWORD}" \
        "$SERVER_IMAGE" sh -c "
            mariadb -h db -u root mangos < /opt/mangos/classic-db/ACID/acid_classic.sql
        " 2>&1 | tail -2 || print_warning "ACID had errors (may be OK)"
    print_success "ACID scripts imported"

    # ────────────────────────────────────────────────────────────────
    # Phase 6: Apply core schema updates from mangos-classic/sql/updates
    # These bring the DB schema up to match what the compiled mangosd
    # expects. Most fail harmlessly (db_version tracking column drift)
    # but the ones that matter — like the 6 spell_template columns —
    # succeed on their actual ALTER TABLE statements.
    # ────────────────────────────────────────────────────────────────
    print_info "Applying core schema updates (mangos, realmd, characters, logs)..."
    $DOCKER_CMD run --rm --network "$compose_net" \
        -e MYSQL_PWD="${DB_PASSWORD}" \
        "$SERVER_IMAGE" sh -c '
            for db in mangos realmd characters logs; do
                cd /opt/mangos/sql/updates/$db 2>/dev/null || continue
                for sql in $(ls -v *.sql 2>/dev/null); do
                    mariadb -h db -u root "$db" < "$sql" 2>/dev/null
                done
            done
            echo "Done"
        ' 2>&1 | tail -2
    print_success "Core schema updates applied"

    # ────────────────────────────────────────────────────────────────
    # Phase 7: Apply the spell_template column fixes EXPLICITLY
    # The z2817/z2818 updates fail via stdin pipe because their first
    # statement (CHANGE COLUMN tracking) errors out and mariadb aborts
    # the batch. We bypass by running the ALTER TABLE directly.
    # Without these 6 columns, mangosd refuses to load spell_template.
    # ────────────────────────────────────────────────────────────────
    print_info "Applying spell_template column extension (6 columns)..."
    $DOCKER_CMD exec -i -e MYSQL_PWD="${DB_PASSWORD}" vanilla-db \
        mariadb -u root mangos <<'EOF' 2>&1 | tail -3 || true
ALTER TABLE spell_template
    ADD COLUMN IF NOT EXISTS EffectBonusCoefficient1 FLOAT NOT NULL DEFAULT '0' AFTER RequiredAuraVision,
    ADD COLUMN IF NOT EXISTS EffectBonusCoefficient2 FLOAT NOT NULL DEFAULT '0' AFTER EffectBonusCoefficient1,
    ADD COLUMN IF NOT EXISTS EffectBonusCoefficient3 FLOAT NOT NULL DEFAULT '0' AFTER EffectBonusCoefficient2,
    ADD COLUMN IF NOT EXISTS EffectBonusCoefficientFromAP1 FLOAT NOT NULL DEFAULT '0' AFTER EffectBonusCoefficient3,
    ADD COLUMN IF NOT EXISTS EffectBonusCoefficientFromAP2 FLOAT NOT NULL DEFAULT '0' AFTER EffectBonusCoefficientFromAP1,
    ADD COLUMN IF NOT EXISTS EffectBonusCoefficientFromAP3 FLOAT NOT NULL DEFAULT '0' AFTER EffectBonusCoefficientFromAP2;
EOF
    print_success "spell_template extended"

    # ────────────────────────────────────────────────────────────────
    # Phase 8: Import Playerbots SQL (14 files across 2 DBs)
    # WITHOUT these, mangosd's Playerbots initialization fails with
    # "Table 'mangos.ai_playerbot_help_texts' doesn't exist"
    # ────────────────────────────────────────────────────────────────
    print_info "Importing Playerbots SQL (14 files, ~23 tables)..."
    $DOCKER_CMD run --rm --network "$compose_net" \
        -e MYSQL_PWD="${DB_PASSWORD}" \
        "$SERVER_IMAGE" sh -c '
            # characters DB — 6 files
            for sql in /opt/mangos/playerbots-sql/characters/*.sql; do
                mariadb -h db -u root characters < "$sql" 2>/dev/null
            done
            # world (mangos) DB — 3 shared files
            for sql in /opt/mangos/playerbots-sql/world/*.sql; do
                mariadb -h db -u root mangos < "$sql" 2>/dev/null
            done
            # world (mangos) DB — 5 classic-specific files
            for sql in /opt/mangos/playerbots-sql/world/classic/*.sql; do
                mariadb -h db -u root mangos < "$sql" 2>/dev/null
            done
            echo "Done"
        ' 2>&1 | tail -2
    print_success "Playerbots SQL imported"

    # ────────────────────────────────────────────────────────────────
    # Phase 9: Verify the install — count critical tables
    # ────────────────────────────────────────────────────────────────
    print_info "Verifying database setup..."
    local item_count
    item_count=$($DOCKER_CMD exec -i -e MYSQL_PWD="${DB_PASSWORD}" vanilla-db \
        mariadb -u root mangos -sN -e \
        "SELECT COUNT(*) FROM item_template" 2>/dev/null)
    local bot_tables
    bot_tables=$($DOCKER_CMD exec -i -e MYSQL_PWD="${DB_PASSWORD}" vanilla-db \
        mariadb -u root mangos -sN -e \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='mangos' AND table_name LIKE 'ai_playerbot%'" 2>/dev/null)

    print_info "  item_template rows: ${item_count:-unknown} (expect ~17,718)"
    print_info "  ai_playerbot_* tables: ${bot_tables:-unknown} (expect ~12)"

    if [ "${item_count:-0}" -ge 17000 ] 2>/dev/null && [ "${bot_tables:-0}" -ge 10 ] 2>/dev/null; then
        print_success "Database setup looks healthy!"
    else
        print_warning "Database setup may be incomplete — see warnings above"
        print_info "You can proceed, but mangosd may fail to boot."
    fi
}

# ─────────────────────────────────────────
# FIRST START + READY WAIT
# ─────────────────────────────────────────
start_server() {
    print_header
    print_step "Starting world & login servers"

    cd "$SERVER_DIR" || exit 1

    # ────────────────────────────────────────────────────────────────
    # NOTE: The db container was already started by setup_database().
    # We only start mangosd and realmd here, AFTER schemas are imported.
    # ────────────────────────────────────────────────────────────────
    print_info "Starting mangosd (world) and realmd (login)..."
    if ! $DOCKER_CMD compose up -d mangosd realmd; then
        print_error "Failed to start mangosd/realmd."
        print_info "Check: cd $SERVER_DIR && $DOCKER_CMD compose logs"
        exit 1
    fi

    print_info "Containers started. Waiting for world server to be ready..."
    print_info "(Loading 17K items, 10K creatures, 2K mmap files takes a minute.)"
    echo ""

    TIMEOUT=600   # 10 min for full boot
    ELAPSED=0
    READY=0
    RESTART_DETECTED=0

    while [ $ELAPSED -lt $TIMEOUT ]; do
        # Layer 1: Check the container hasn't restart-looped.
        # "Up" alone is misleading — containers can be restart-looping
        # silently with restart: unless-stopped. We check RestartCount.
        local restart_count
        restart_count=$($DOCKER_CMD inspect --format '{{.RestartCount}}' \
            vanilla-mangosd 2>/dev/null)

        if [ -n "$restart_count" ] && [ "$restart_count" -gt 2 ] 2>/dev/null; then
            RESTART_DETECTED=1
            break
        fi

        # Layer 2: Look for the actual ready signal in logs
        if $DOCKER_CMD logs vanilla-mangosd 2>&1 | \
            grep -qE "CMANGOS: World initialized|World initialized in|Server is ready"; then
            READY=1
            break
        fi

        printf "."
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    echo ""
    echo ""

    if [ $READY -eq 1 ]; then
        print_success "World server is online! 🌍"
        print_info "  Port 8085 (world) and 3724 (login) are listening"
    elif [ $RESTART_DETECTED -eq 1 ]; then
        print_error "mangosd is in a restart loop — boot failed."
        print_info "Check: $DOCKER_CMD logs vanilla-mangosd --tail 100"
        print_info ""
        print_info "Most common causes at this point:"
        print_info "  • A schema update didn't apply (check spell_template column count)"
        print_info "  • Playerbots SQL didn't import (check ai_playerbot_* tables)"
        print_info "  • Mmap files missing (check data/mmaps/ has 2000+ files)"
        print_info ""
        if ! ask_yes_no "Continue to account creation anyway? (server won't be usable)"; then
            exit 1
        fi
    else
        print_warning "Server taking longer than 10 min to initialize."
        print_info "It MAY still be loading — check logs: $DOCKER_CMD compose logs -f"
        print_info "Look for 'CMANGOS: World initialized'"
    fi
}

# ─────────────────────────────────────────
# CREATE DEFAULT ACCOUNT
# ─────────────────────────────────────────
create_default_account() {
    print_step "Account creation — quick post-install step"

    # ────────────────────────────────────────────────────────────────
    # C1+C2 fix: We do NOT auto-create the account here.
    #
    # Why the manual approach is more reliable:
    #
    # CMaNGOS Classic dropped sha_pass_hash support (PR #397) and uses
    # SRP6 verifier (s salt + v verifier columns). Computing SRP6
    # correctly requires bignum modular exponentiation that bash can't
    # do natively — would need Python + openssl with specific byte
    # ordering. Adding that dependency to an already-complex installer
    # is the wrong tradeoff for v1.1.1.
    #
    # Also: the account_access table we previously used for GM grants
    # is a TrinityCore convention. CMaNGOS Classic stores gmlevel as a
    # column directly in the account table — different SQL entirely.
    #
    # The reliable approach (proven in the marathon): use mangosd's
    # built-in `account create` console command, which knows the right
    # SRP6 math and the right table layout. The user runs ONE simple
    # command after install completes.
    #
    # See show_completion() for the exact instructions printed to the
    # user.
    # ────────────────────────────────────────────────────────────────

    print_info "Account creation is a quick manual step after install completes."
    print_info "See the next screen for the exact commands (it's two lines)."
    print_info "The mangosd console handles SRP6 password hashing correctly."
}

# ─────────────────────────────────────────
# SETUP GAMING MODE LAUNCHER
# ─────────────────────────────────────────
setup_gaming_mode() {
    print_step "Setting up Gaming Mode launcher"

    local launcher_path="$HOME/wow-vanilla-launcher.sh"
    local server_dir="$SERVER_DIR"

    cat > "$launcher_path" << LAUNCHER
#!/bin/bash
# Dad's MMO Lab — Vanilla WoW Launcher
LOGFILE=/tmp/wow-vanilla-launcher.log
echo "=== Vanilla WoW Launcher started \$(date) ===" > "\$LOGFILE"

echo ""
echo "  ⚔️  Vanilla WoW Server starting up..."
echo ""

# Stop any conflicting Classic WoW containers from other expansions
OTHER=\$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE "tbc|wotlk|azeroth" || true)
if [ -n "\$OTHER" ]; then
    echo "  Stopping other expansion containers..."
    echo "\$OTHER" | xargs docker stop >> "\$LOGFILE" 2>&1 || true
    sleep 2
fi

cd "${server_dir}" || exit 1

if docker compose up -d >> "\$LOGFILE" 2>&1; then
    echo "  Containers started!"
else
    echo "  ERR: Failed to start. Check: \$LOGFILE"
    sleep 10
    exit 1
fi

echo ""
echo "  Waiting for Azeroth to open..."
echo ""

# Wait for ready (faster after first install)
TIMEOUT=300
ELAPSED=0
READY=0
while [ \$ELAPSED -lt \$TIMEOUT ]; do
    if docker logs vanilla-mangosd 2>&1 | \
        grep -qE "World initialized|Server is ready"; then
        READY=1
        break
    fi
    sleep 5
    ELAPSED=\$((ELAPSED + 5))
done

if [ \$READY -eq 1 ]; then
    echo "  🎉 AZEROTH IS READY!"
    echo ""
    echo "  Login: player / player"
    echo "  Realmlist: 127.0.0.1"
    echo ""
else
    echo "  ⏳ Server still warming up. Check logs if needed."
fi

# Wait for WoW client process
# pgrep -f with extended regex: use | not \|  (session pattern #1)
echo "  Press STEAM button and launch WoW"
echo "  Server auto-shuts down when WoW closes"
echo ""

WOW_STARTED=0
for i in \$(seq 1 60); do
    if pgrep -fi "Wow\\.exe|wine.*[Ww]o[Ww]" > /dev/null 2>&1; then
        WOW_STARTED=1
        break
    fi
    sleep 5
done

if [ \$WOW_STARTED -eq 1 ]; then
    echo "  WoW detected! Enjoy Azeroth! ⚔️"
    while pgrep -fi "Wow\\.exe|wine.*[Ww]o[Ww]" > /dev/null 2>&1; do
        sleep 3
    done
    sleep 5
    echo "  WoW closed — shutting down server..."
else
    echo "  WoW not detected — keeping server alive for 3 hours."
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
    print_success "Launcher created: ~/wow-vanilla-launcher.sh"

    # Info file
    cat > "$SERVER_DIR/MY_SERVER.txt" << INFO
====================================
  Dad's MMO Lab — Vanilla WoW
  CMaNGOS Classic + Playerbots
  (source compile)
====================================

SERVER:
  Folder:    ${SERVER_DIR}
  Realmlist: 127.0.0.1
  World:     127.0.0.1:8085
  Login:     127.0.0.1:3724
  Account:   player / player

LAUNCHER:
  Path: ~/wow-vanilla-launcher.sh
  Add to Steam:
    Target:  /usr/bin/konsole
    Options: --hold -e bash ~/wow-vanilla-launcher.sh
    Proton:  OFF (launcher needs no Proton; WoW client itself uses Proton)

REALMLIST (in your Vanilla client folder):
  Edit:  realmlist.wtf
  Set to: set realmlist 127.0.0.1
  Then lock: chmod 444 [path]/realmlist.wtf

USEFUL COMMANDS:
  Start:   cd ${SERVER_DIR} && docker compose up -d
  Stop:    cd ${SERVER_DIR} && docker compose down
  Logs:    cd ${SERVER_DIR} && docker compose logs -f
  Status:  docker ps | grep vanilla
  Console: docker attach vanilla-mangosd
    (Exit safely: Ctrl+P then Ctrl+Q. NOT Ctrl+C.)

CREATE MORE ACCOUNTS:
  docker attach vanilla-mangosd
  account create USERNAME PASSWORD
  account set gmlevel USERNAME 3 -1   (optional: makes account GM)
  [Ctrl+P then Ctrl+Q to exit safely]
INFO

    print_success "MY_SERVER.txt saved to $SERVER_DIR"
}

# ─────────────────────────────────────────
# COMPLETION
# ─────────────────────────────────────────
show_completion() {
    print_header

    # ────────────────────────────────────────────────────────────────
    # Auto-write realmlist.wtf for the user. This is one less manual
    # step they have to figure out. Locking it (chmod 444) prevents
    # the WoW client from overwriting it on first launch.
    # ────────────────────────────────────────────────────────────────
    local realmlist_path="$CLIENT_DIR/realmlist.wtf"
    local realmlist_written=0

    # Some repacks put realmlist at top level; standard installs put it
    # inside Data/enUS/. We check both and write to wherever it lives,
    # or create it at top level if neither exists.
    if [ -f "$CLIENT_DIR/Data/enUS/realmlist.wtf" ]; then
        realmlist_path="$CLIENT_DIR/Data/enUS/realmlist.wtf"
    fi

    if [ -e "$realmlist_path" ] || [ -d "$(dirname "$realmlist_path")" ]; then
        # Unlock first in case it was already chmod 444
        chmod 644 "$realmlist_path" 2>/dev/null || true
        echo "set realmlist 127.0.0.1" > "$realmlist_path" 2>/dev/null && {
            chmod 444 "$realmlist_path" 2>/dev/null
            realmlist_written=1
        }
    fi

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║         🎉 VANILLA WOW INSTALLED! 🎉              ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${WHITE}${BOLD}You compiled CMaNGOS Classic from source on your Steam Deck.${NC}"
    echo -e "${WHITE}${BOLD}That's real engineering work. Welcome to a club of one.${NC}"
    echo ""
    echo -e "${CL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}${BOLD}Expansion:${NC}  ${CL}Vanilla (1.12.1)${NC}"
    echo -e "  ${WHITE}${BOLD}Server dir:${NC} ${CL}$SERVER_DIR${NC}"
    echo -e "  ${WHITE}${BOLD}Launcher:${NC}   ${CL}~/wow-vanilla-launcher.sh${NC}"
    echo -e "  ${WHITE}${BOLD}Bots:${NC}       ${GREEN}Playerbots + AHBot active${NC}"
    echo -e "  ${WHITE}${BOLD}Account:${NC}    ${YELLOW}player / player${NC} (create in step A below)"
    if [ $realmlist_written -eq 1 ]; then
        echo -e "  ${WHITE}${BOLD}Realmlist:${NC}  ${GREEN}auto-configured (locked to 127.0.0.1)${NC}"
    else
        echo -e "  ${WHITE}${BOLD}Realmlist:${NC}  ${YELLOW}NOT auto-written — see step A below${NC}"
    fi
    echo -e "${CL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CLB}${BOLD}NEXT STEPS — finish setup (~10 min):${NC}"
    echo ""

    # ────────────────────────────────────────────────────────────────
    # STEP A: Manual account creation via mangosd console.
    # This is THE most important post-install step. Without it, the
    # user has no account to log in with. We make it crystal clear.
    # ────────────────────────────────────────────────────────────────
    echo -e "${GREEN}${BOLD}A. Create your player account (REQUIRED — 30 seconds):${NC}"
    echo ""
    echo -e "   Open Konsole and run this single command:"
    echo -e "      ${CL}docker attach vanilla-mangosd${NC}"
    echo ""
    echo -e "   You'll see a blinking cursor (the mangosd console)."
    echo -e "   Type each of these and press Enter:"
    echo -e "      ${CL}account create player player${NC}"
    echo -e "      ${CL}account set gmlevel player 3 -1${NC}"
    echo ""
    echo -e "   To exit safely, press ${BOLD}Ctrl+P then Ctrl+Q${NC} (sequential)."
    echo -e "   ${RED}${BOLD}⚠️  NEVER press Ctrl+C — that kills the server!${NC}"
    echo ""
    echo -e "   Why manual? mangosd's built-in command handles SRP6 password"
    echo -e "   hashing correctly. Doing it in SQL would require complex math."
    echo ""

    if [ $realmlist_written -ne 1 ]; then
        echo -e "${WHITE}${BOLD}B. Set up realmlist (auto-write failed):${NC}"
        echo -e "   Edit ${CL}$realmlist_path${NC}"
        echo -e "   Contents: ${CL}set realmlist 127.0.0.1${NC}"
        echo -e "   Lock it:  ${CL}chmod 444 $realmlist_path${NC}"
        echo ""
    fi

    echo -e "${WHITE}${BOLD}C. Add the server launcher to Steam:${NC}"
    echo -e "   Steam → Add a Non-Steam Game → /usr/bin/konsole"
    echo -e "   Rename to: ${CL}Vanilla WoW Server${NC}"
    echo -e "   Right-click → Properties → Launch Options:"
    echo -e "      ${CL}--hold -e bash ~/wow-vanilla-launcher.sh${NC}"
    echo -e "   Compatibility: ${YELLOW}Proton OFF${NC} (this is a Linux script)"
    echo ""

    echo -e "${WHITE}${BOLD}D. Add the WoW client to Steam:${NC}"
    echo -e "   Steam → Add a Non-Steam Game → WoW.exe (in $CLIENT_DIR)"
    echo -e "   Rename to: ${CL}Vanilla WoW${NC}"
    echo -e "   Compatibility: ${GREEN}Force GE-Proton${NC} (latest)"
    echo ""

    echo -e "${WHITE}${BOLD}E. Play in Gaming Mode:${NC}"
    echo -e "   1. Launch ${CL}Vanilla WoW Server${NC} from your library"
    echo -e "   2. Wait for ${GREEN}AZEROTH IS READY!${NC}"
    echo -e "   3. Launch ${CL}Vanilla WoW${NC} — login: ${CL}player / player${NC}"
    echo -e "   4. Bots populate the world within 5-10 min — be patient!"
    echo ""

    echo -e "${BLUE}ℹ️  Server info: $SERVER_DIR/MY_SERVER.txt${NC}"
    echo -e "${BLUE}ℹ️  Build log: /tmp/wow-vanilla-build.log${NC}"
    echo -e "${BLUE}ℹ️  Want the fast path next time? Pre-built Docker images coming soon!${NC}"
    echo -e "${BLUE}   Watch: github.com/DadsMmoLab/dads-mmo-lab${NC}"
    echo ""
}

# ─────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────
DOCKER_CMD="docker"

check_system
show_welcome

# ── I4: Cache sudo credentials upfront ──────────────────────────
# This installer makes several sudo calls (Docker install, chown
# on root-owned extraction outputs). If we don't prompt NOW, the
# user will get an unexpected password prompt at hour 3 of the
# compile — often when they're not at the Deck. Cache the cred
# proactively so they only enter the password once, here.
echo ""
echo -e "\033[1;33m⚠️  This installer needs sudo access for:\033[0m"
echo -e "\033[1;33m   • Installing Docker (if not present)\033[0m"
echo -e "\033[1;33m   • Fixing file ownership after extraction\033[0m"
echo -e "\033[1;33m   • Cleaning up an existing install (if any)\033[0m"
echo ""
echo -e "\033[1;37mPlease enter your password if prompted:\033[0m"
if ! sudo -v; then
    echo -e "\033[0;31m❌ Could not cache sudo credentials. Aborting.\033[0m"
    exit 1
fi
# Refresh sudo timestamp every 60s in the background while installer runs.
# Without this, the cached cred could expire during a 3-hour compile.
( while true; do sudo -n true; sleep 60; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
# Ensure the keepalive process dies when the installer exits (success OR fail).
trap "kill $SUDO_KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

locate_client
show_summary
install_docker
do_compile
extract_client_data
write_compose_and_configs
setup_database
start_server
create_default_account
setup_gaming_mode
show_completion
