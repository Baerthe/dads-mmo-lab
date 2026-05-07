#!/bin/bash
# ============================================================
#  Dad's MMO Lab — Character & Account Migration Tool
#  Move characters and accounts between server versions
#
#  https://github.com/DadsMmoLab/dads-mmo-lab
#
#  Usage:
#    chmod +x migrate.sh
#    ./migrate.sh
#
#  What this can do:
#    1. Migrate a full account + all characters between servers
#    2. Copy a single character between servers
#    3. Move a character between accounts on the same server
#    4. List all accounts and characters on any server
#
#  Supported servers:
#    - Standard AzerothCore (~/wow-server)
#    - NPCBots AzerothCore (~/wow-server-npcbots)
#
#  ⚠️  ALWAYS backs up before making any changes!
# ============================================================

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

print_header() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}${BOLD}         ⚙️  DAD'S MMO LAB                        ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}         Character & Account Migration Tool        ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${BLUE}         github.com/DadsMmoLab/dads-mmo-lab       ${NC}${CYAN}║${NC}"
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

press_enter() {
    echo ""
    echo -e "${WHITE}Press ENTER to continue...${NC}"
    read -r
}

# ─────────────────────────────────────────
# SERVER DEFINITIONS
# ─────────────────────────────────────────
STANDARD_DIR="$HOME/wow-server"
NPCBOTS_DIR="$HOME/wow-server-npcbots"
BACKUP_DIR="$HOME/wow-migration-backups"

# Detect container names dynamically
get_db_container() {
    local server_dir="$1"
    local folder_name
    folder_name=$(basename "$server_dir")

    # Try to find running container
    local container
    container=$(docker ps --format '{{.Names}}' 2>/dev/null \
        | grep -i "database" | head -1)

    if [ -n "$container" ]; then
        echo "$container"
    else
        # Fallback based on folder name
        case "$folder_name" in
            "wow-server-npcbots") echo "ac-database" ;;
            *) echo "wow-server-ac-database-1" ;;
        esac
    fi
}

get_world_container() {
    local container
    container=$(docker ps --format '{{.Names}}' 2>/dev/null \
        | grep -i "worldserver" | head -1)
    echo "${container:-acore-docker-ac-worldserver-1}"
}

# ─────────────────────────────────────────
# HELPER: Check if server is running
# ─────────────────────────────────────────
is_server_running() {
    local server_dir="$1"
    local folder_name
    folder_name=$(basename "$server_dir")
    docker ps 2>/dev/null | grep -q "database" && return 0 || return 1
}

# ─────────────────────────────────────────
# HELPER: Start a server
# ─────────────────────────────────────────
start_server() {
    local server_dir="$1"
    local server_name="$2"

    print_info "Starting $server_name server..."
    cd "$server_dir" || return 1
    docker compose up -d --scale phpmyadmin=0 2>/dev/null || \
    docker compose up -d 2>/dev/null

    # Wait for DB to be healthy
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local db
        db=$(get_db_container "$server_dir")
        if docker exec "$db" mysqladmin ping -uroot -ppassword \
            &>/dev/null 2>&1; then
            print_success "$server_name database is ready!"
            return 0
        fi
        printf "."
        sleep 3
        elapsed=$((elapsed + 3))
    done

    print_error "$server_name failed to start!"
    return 1
}

# ─────────────────────────────────────────
# HELPER: Stop a server
# ─────────────────────────────────────────
stop_server() {
    local server_dir="$1"
    local server_name="$2"

    print_info "Stopping $server_name server..."
    cd "$server_dir" || return 1
    docker compose down 2>/dev/null
    sleep 2
    print_success "$server_name stopped!"
}

# ─────────────────────────────────────────
# HELPER: Run MySQL query
# ─────────────────────────────────────────
mysql_query() {
    local container="$1"
    local db="$2"
    local query="$3"
    docker exec "$container" mysql -uroot -ppassword "$db" \
        -sNe "$query" 2>/dev/null
}

mysql_exec() {
    local container="$1"
    local db="$2"
    local query="$3"
    docker exec "$container" mysql -uroot -ppassword "$db" \
        -e "$query" 2>/dev/null
}

# ─────────────────────────────────────────
# HELPER: Create backup
# ─────────────────────────────────────────
create_backup() {
    local container="$1"
    local label="$2"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/${label}_${timestamp}.sql"

    mkdir -p "$BACKUP_DIR"
    print_info "Creating backup: $backup_file"

    docker exec "$container" mysqldump \
        -uroot -ppassword \
        --databases acore_auth acore_characters acore_world \
        > "$backup_file" 2>/dev/null

    if [ -s "$backup_file" ]; then
        local size
        size=$(du -sh "$backup_file" | cut -f1)
        print_success "Backup created! ($size) — $backup_file"
        echo "$backup_file"
        return 0
    else
        print_error "Backup failed!"
        return 1
    fi
}

# ─────────────────────────────────────────
# FEATURE 1: List all accounts & characters
# ─────────────────────────────────────────
list_accounts_and_characters() {
    local server_dir="$1"
    local server_name="$2"

    print_step "📋 Accounts & Characters — $server_name"

    if ! is_server_running "$server_dir"; then
        print_warning "$server_name is not running."
        echo -e "${WHITE}Start it? (y/n): ${NC}"
        read -r ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            start_server "$server_dir" "$server_name" || return 1
        else
            return 1
        fi
    fi

    local db_container
    db_container=$(get_db_container "$server_dir")

    echo ""
    echo -e "${WHITE}${BOLD}ACCOUNTS:${NC}"
    echo "─────────────────────────────────────────"

    # Get all accounts
    local accounts
    accounts=$(mysql_query "$db_container" "acore_auth" \
        "SELECT id, username FROM account ORDER BY id;")

    if [ -z "$accounts" ]; then
        print_warning "No accounts found."
        return 0
    fi

    while IFS=$'\t' read -r acc_id acc_name; do
        echo ""
        echo -e "  ${CYAN}Account:${NC} ${WHITE}${acc_name}${NC} (ID: ${acc_id})"

        # Get characters for this account
        local chars
        chars=$(mysql_query "$db_container" "acore_characters" \
            "SELECT guid, name, race, class, level
             FROM characters
             WHERE account = ${acc_id}
             ORDER BY level DESC;")

        if [ -z "$chars" ]; then
            echo -e "    ${YELLOW}No characters${NC}"
        else
            while IFS=$'\t' read -r guid name race class level; do
                # Convert race/class numbers to names
                local race_name class_name
                case "$race" in
                    1) race_name="Human" ;; 2) race_name="Orc" ;;
                    3) race_name="Dwarf" ;; 4) race_name="Night Elf" ;;
                    5) race_name="Undead" ;; 6) race_name="Tauren" ;;
                    7) race_name="Gnome" ;; 8) race_name="Troll" ;;
                    10) race_name="Blood Elf" ;; 11) race_name="Draenei" ;;
                    *) race_name="Race $race" ;;
                esac
                case "$class" in
                    1) class_name="Warrior" ;; 2) class_name="Paladin" ;;
                    3) class_name="Hunter" ;; 4) class_name="Rogue" ;;
                    5) class_name="Priest" ;; 6) class_name="Death Knight" ;;
                    7) class_name="Shaman" ;; 8) class_name="Mage" ;;
                    9) class_name="Warlock" ;; 11) class_name="Druid" ;;
                    *) class_name="Class $class" ;;
                esac
                echo -e "    ${GREEN}▸${NC} ${WHITE}${name}${NC} — Level ${level} ${race_name} ${class_name} (GUID: ${guid})"
            done <<< "$chars"
        fi
    done <<< "$accounts"

    echo ""
    echo "─────────────────────────────────────────"
    press_enter
}

# ─────────────────────────────────────────
# FEATURE 2: Migrate full account between servers
# ─────────────────────────────────────────
migrate_full_account() {
    print_step "🔄 Migrate Full Account Between Servers"

    echo ""
    echo -e "${WHITE}Which server are you migrating FROM?${NC}"
    echo -e "  1) Standard WoW ($STANDARD_DIR)"
    echo -e "  2) NPCBots WoW ($NPCBOTS_DIR)"
    echo -e "${WHITE}Choice (1-2): ${NC}"
    read -r src_choice

    case "$src_choice" in
        1) SRC_DIR="$STANDARD_DIR"; SRC_NAME="Standard WoW" ;;
        2) SRC_DIR="$NPCBOTS_DIR";  SRC_NAME="NPCBots WoW" ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac

    echo ""
    echo -e "${WHITE}Which server are you migrating TO?${NC}"
    echo -e "  1) Standard WoW ($STANDARD_DIR)"
    echo -e "  2) NPCBots WoW ($NPCBOTS_DIR)"
    echo -e "${WHITE}Choice (1-2): ${NC}"
    read -r dst_choice

    case "$dst_choice" in
        1) DST_DIR="$STANDARD_DIR"; DST_NAME="Standard WoW" ;;
        2) DST_DIR="$NPCBOTS_DIR";  DST_NAME="NPCBots WoW" ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac

    if [ "$SRC_DIR" = "$DST_DIR" ]; then
        print_error "Source and destination can't be the same server!"
        return 1
    fi

    # Start source server if needed
    if ! is_server_running "$SRC_DIR"; then
        start_server "$SRC_DIR" "$SRC_NAME" || return 1
    fi

    # Show accounts on source
    local src_db
    src_db=$(get_db_container "$SRC_DIR")

    echo ""
    echo -e "${WHITE}Accounts on $SRC_NAME:${NC}"
    mysql_query "$src_db" "acore_auth" \
        "SELECT id, username FROM account ORDER BY username;" \
        | while IFS=$'\t' read -r id name; do
            echo -e "  ${CYAN}[$id]${NC} $name"
        done

    echo ""
    echo -e "${WHITE}Enter the USERNAME to migrate: ${NC}"
    read -r MIGRATE_USER
    MIGRATE_USER="${MIGRATE_USER^^}" # uppercase

    # Verify account exists
    local acc_id
    acc_id=$(mysql_query "$src_db" "acore_auth" \
        "SELECT id FROM account WHERE username='${MIGRATE_USER}';")

    if [ -z "$acc_id" ]; then
        print_error "Account '$MIGRATE_USER' not found on $SRC_NAME!"
        return 1
    fi

    print_success "Found account: $MIGRATE_USER (ID: $acc_id)"

    # Show characters
    echo ""
    echo -e "${WHITE}Characters on this account:${NC}"
    mysql_query "$src_db" "acore_characters" \
        "SELECT name, level FROM characters WHERE account=$acc_id;" \
        | while IFS=$'\t' read -r name level; do
            echo -e "  ${GREEN}▸${NC} $name (Level $level)"
        done

    echo ""
    echo -e "${YELLOW}This will copy the account AND all characters to $DST_NAME.${NC}"
    echo -e "${WHITE}Continue? (y/n): ${NC}"
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return 0

    # Backup both servers first
    print_step "Creating Safety Backups"
    create_backup "$src_db" "pre_migrate_source" || return 1

    # Start destination server
    stop_server "$SRC_DIR" "$SRC_NAME"
    start_server "$DST_DIR" "$DST_NAME" || return 1

    local dst_db
    dst_db=$(get_db_container "$DST_DIR")

    create_backup "$dst_db" "pre_migrate_destination" || return 1

    print_step "Migrating Account & Characters"

    # Export auth data for this account
    print_info "Exporting account data..."
    local auth_data
    auth_data=$(docker exec "$src_db" mysqldump \
        -uroot -ppassword \
        --no-create-info --skip-triggers \
        --where="id=${acc_id}" \
        acore_auth account account_access 2>/dev/null)

    # Export character data
    print_info "Exporting character data..."
    local char_guids
    char_guids=$(mysql_query "$src_db" "acore_characters" \
        "SELECT GROUP_CONCAT(guid) FROM characters WHERE account=${acc_id};")

    # Check if account already exists on destination
    local existing_id
    existing_id=$(mysql_query "$dst_db" "acore_auth" \
        "SELECT id FROM account WHERE username='${MIGRATE_USER}';")

    if [ -n "$existing_id" ]; then
        print_warning "Account '$MIGRATE_USER' already exists on $DST_NAME (ID: $existing_id)"
        echo -e "${WHITE}Overwrite it? (y/n): ${NC}"
        read -r overwrite
        if [[ "$overwrite" =~ ^[Yy]$ ]]; then
            mysql_exec "$dst_db" "acore_auth" \
                "DELETE FROM account_access WHERE id=$existing_id;"
            mysql_exec "$dst_db" "acore_auth" \
                "DELETE FROM account WHERE id=$existing_id;"
            # Remove existing characters
            mysql_exec "$dst_db" "acore_characters" \
                "DELETE FROM characters WHERE account=$existing_id;"
        else
            print_info "Migration cancelled."
            return 0
        fi
    fi

    # Import account using same ID to preserve character links
    print_info "Importing account to $DST_NAME..."

    # Get full account row
    local acc_row
    acc_row=$(mysql_query "$src_db" "acore_auth" \
        "SELECT * FROM account WHERE id=${acc_id};" | head -1)

    # Copy account row directly
    docker exec "$src_db" mysqldump \
        -uroot -ppassword \
        --no-create-info \
        --where="id=${acc_id}" \
        acore_auth account 2>/dev/null | \
    docker exec -i "$dst_db" mysql \
        -uroot -ppassword acore_auth 2>/dev/null

    # Copy account access (GM level)
    docker exec "$src_db" mysqldump \
        -uroot -ppassword \
        --no-create-info \
        --where="id=${acc_id}" \
        acore_auth account_access 2>/dev/null | \
    docker exec -i "$dst_db" mysql \
        -uroot -ppassword acore_auth 2>/dev/null

    # Copy all character data
    if [ -n "$char_guids" ] && [ "$char_guids" != "NULL" ]; then
        print_info "Importing characters..."

        local char_tables=(
            "characters"
            "character_inventory"
            "character_queststatus"
            "character_queststatus_rewarded"
            "character_spell"
            "character_skills"
            "character_reputation"
            "character_talent"
            "character_action"
            "character_aura"
            "character_homebind"
            "character_social"
            "character_achievement"
            "character_achievement_progress"
        )

        for table in "${char_tables[@]}"; do
            # Check if table has a guid column
            local has_guid
            has_guid=$(mysql_query "$src_db" "acore_characters" \
                "SHOW COLUMNS FROM $table LIKE 'guid';" 2>/dev/null)

            if [ -n "$has_guid" ]; then
                docker exec "$src_db" mysqldump \
                    -uroot -ppassword \
                    --no-create-info \
                    --replace \
                    --where="guid IN ($char_guids)" \
                    acore_characters "$table" 2>/dev/null | \
                docker exec -i "$dst_db" mysql \
                    -uroot -ppassword acore_characters 2>/dev/null
            fi
        done

        print_success "Characters imported!"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   ✅ MIGRATION COMPLETE!                          ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Account ${WHITE}${MIGRATE_USER}${NC} has been migrated to ${CYAN}$DST_NAME${NC}"
    echo -e "  Login with your same username and password!"
    echo ""
    print_info "Backups saved to: $BACKUP_DIR"
    press_enter
}

# ─────────────────────────────────────────
# FEATURE 3: Copy single character
# ─────────────────────────────────────────
copy_single_character() {
    print_step "👤 Copy Single Character Between Servers"

    echo ""
    echo -e "${WHITE}Copy FROM which server?${NC}"
    echo -e "  1) Standard WoW ($STANDARD_DIR)"
    echo -e "  2) NPCBots WoW ($NPCBOTS_DIR)"
    echo -e "${WHITE}Choice (1-2): ${NC}"
    read -r src_choice

    case "$src_choice" in
        1) SRC_DIR="$STANDARD_DIR"; SRC_NAME="Standard WoW" ;;
        2) SRC_DIR="$NPCBOTS_DIR";  SRC_NAME="NPCBots WoW" ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac

    echo ""
    echo -e "${WHITE}Copy TO which server?${NC}"
    echo -e "  1) Standard WoW ($STANDARD_DIR)"
    echo -e "  2) NPCBots WoW ($NPCBOTS_DIR)"
    echo -e "${WHITE}Choice (1-2): ${NC}"
    read -r dst_choice

    case "$dst_choice" in
        1) DST_DIR="$STANDARD_DIR"; DST_NAME="Standard WoW" ;;
        2) DST_DIR="$NPCBOTS_DIR";  DST_NAME="NPCBots WoW" ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac

    # Start source
    if ! is_server_running "$SRC_DIR"; then
        start_server "$SRC_DIR" "$SRC_NAME" || return 1
    fi

    local src_db
    src_db=$(get_db_container "$SRC_DIR")

    # Show all characters
    echo ""
    echo -e "${WHITE}Characters on $SRC_NAME:${NC}"
    mysql_query "$src_db" "acore_characters" \
        "SELECT c.guid, c.name, c.level, a.username
         FROM characters c
         JOIN acore_auth.account a ON c.account = a.id
         ORDER BY c.name;" \
        | while IFS=$'\t' read -r guid name level account; do
            echo -e "  ${GREEN}▸${NC} ${WHITE}${name}${NC} — Level $level (Account: $account) [GUID: $guid]"
        done

    echo ""
    echo -e "${WHITE}Enter the CHARACTER NAME to copy: ${NC}"
    read -r CHAR_NAME

    # Find character
    local char_guid char_acc_id
    char_guid=$(mysql_query "$src_db" "acore_characters" \
        "SELECT guid FROM characters WHERE name='${CHAR_NAME}';")
    char_acc_id=$(mysql_query "$src_db" "acore_characters" \
        "SELECT account FROM characters WHERE name='${CHAR_NAME}';")

    if [ -z "$char_guid" ]; then
        print_error "Character '$CHAR_NAME' not found!"
        return 1
    fi

    print_success "Found: $CHAR_NAME (GUID: $char_guid)"

    echo ""
    echo -e "${WHITE}Which account on $DST_NAME should receive this character?${NC}"

    # Start destination to check accounts
    stop_server "$SRC_DIR" "$SRC_NAME"
    start_server "$DST_DIR" "$DST_NAME" || return 1

    local dst_db
    dst_db=$(get_db_container "$DST_DIR")

    mysql_query "$dst_db" "acore_auth" \
        "SELECT id, username FROM account ORDER BY username;" \
        | while IFS=$'\t' read -r id name; do
            echo -e "  ${CYAN}[$id]${NC} $name"
        done

    echo ""
    echo -e "${WHITE}Enter destination account USERNAME: ${NC}"
    read -r DST_ACCOUNT
    DST_ACCOUNT="${DST_ACCOUNT^^}"

    local dst_acc_id
    dst_acc_id=$(mysql_query "$dst_db" "acore_auth" \
        "SELECT id FROM account WHERE username='${DST_ACCOUNT}';")

    if [ -z "$dst_acc_id" ]; then
        print_error "Account '$DST_ACCOUNT' not found on $DST_NAME!"
        print_info "Create the account first, then run migration again."
        return 1
    fi

    echo ""
    echo -e "${YELLOW}This will COPY $CHAR_NAME to $DST_NAME under account $DST_ACCOUNT.${NC}"
    echo -e "${YELLOW}The original character on $SRC_NAME will be untouched.${NC}"
    echo -e "${WHITE}Continue? (y/n): ${NC}"
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return 0

    # Backup destination
    create_backup "$dst_db" "pre_char_copy_destination" || return 1

    print_info "Copying character data..."

    # We need to start source briefly to export
    stop_server "$DST_DIR" "$DST_NAME"
    start_server "$SRC_DIR" "$SRC_NAME" || return 1
    src_db=$(get_db_container "$SRC_DIR")

    # Export character tables
    local char_tables=(
        "characters"
        "character_inventory"
        "character_queststatus"
        "character_queststatus_rewarded"
        "character_spell"
        "character_skills"
        "character_reputation"
        "character_talent"
        "character_action"
        "character_aura"
        "character_homebind"
        "character_achievement"
        "character_achievement_progress"
    )

    # Save exports to temp files
    mkdir -p /tmp/wow_char_export

    for table in "${char_tables[@]}"; do
        local has_guid
        has_guid=$(mysql_query "$src_db" "acore_characters" \
            "SHOW COLUMNS FROM $table LIKE 'guid';" 2>/dev/null)
        if [ -n "$has_guid" ]; then
            docker exec "$src_db" mysqldump \
                -uroot -ppassword \
                --no-create-info \
                --replace \
                --where="guid=${char_guid}" \
                acore_characters "$table" \
                > "/tmp/wow_char_export/${table}.sql" 2>/dev/null
        fi
    done

    print_success "Character data exported!"

    # Switch to destination
    stop_server "$SRC_DIR" "$SRC_NAME"
    start_server "$DST_DIR" "$DST_NAME" || return 1
    dst_db=$(get_db_container "$DST_DIR")

    # Import all tables
    for table in "${char_tables[@]}"; do
        if [ -f "/tmp/wow_char_export/${table}.sql" ]; then
            docker exec -i "$dst_db" mysql \
                -uroot -ppassword acore_characters \
                < "/tmp/wow_char_export/${table}.sql" 2>/dev/null
        fi
    done

    # Update account ID to destination account
    mysql_exec "$dst_db" "acore_characters" \
        "UPDATE characters SET account=${dst_acc_id} WHERE guid=${char_guid};"

    # Clean up temp files
    rm -rf /tmp/wow_char_export

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   ✅ CHARACTER COPY COMPLETE!                     ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}${CHAR_NAME}${NC} is now on ${CYAN}$DST_NAME${NC}"
    echo -e "  under account ${WHITE}${DST_ACCOUNT}${NC}!"
    echo ""
    press_enter
}

# ─────────────────────────────────────────
# FEATURE 4: Move character between accounts
# ─────────────────────────────────────────
move_character_between_accounts() {
    print_step "🔀 Move Character Between Accounts (Same Server)"

    echo ""
    echo -e "${WHITE}Which server?${NC}"
    echo -e "  1) Standard WoW ($STANDARD_DIR)"
    echo -e "  2) NPCBots WoW ($NPCBOTS_DIR)"
    echo -e "${WHITE}Choice (1-2): ${NC}"
    read -r srv_choice

    case "$srv_choice" in
        1) SRV_DIR="$STANDARD_DIR"; SRV_NAME="Standard WoW" ;;
        2) SRV_DIR="$NPCBOTS_DIR";  SRV_NAME="NPCBots WoW" ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac

    if ! is_server_running "$SRV_DIR"; then
        start_server "$SRV_DIR" "$SRV_NAME" || return 1
    fi

    local db
    db=$(get_db_container "$SRV_DIR")

    # Show characters and accounts
    echo ""
    echo -e "${WHITE}All characters on $SRV_NAME:${NC}"
    mysql_query "$db" "acore_characters" \
        "SELECT c.guid, c.name, c.level, a.username
         FROM characters c
         JOIN acore_auth.account a ON c.account = a.id
         ORDER BY a.username, c.name;" \
        | while IFS=$'\t' read -r guid name level account; do
            echo -e "  ${GREEN}▸${NC} ${WHITE}${name}${NC} (Level $level) — currently on account: ${CYAN}$account${NC}"
        done

    echo ""
    echo -e "${WHITE}Enter the CHARACTER NAME to move: ${NC}"
    read -r CHAR_NAME

    local char_guid char_current_acc
    char_guid=$(mysql_query "$db" "acore_characters" \
        "SELECT guid FROM characters WHERE name='${CHAR_NAME}';")
    char_current_acc=$(mysql_query "$db" "acore_characters" \
        "SELECT a.username FROM characters c
         JOIN acore_auth.account a ON c.account=a.id
         WHERE c.name='${CHAR_NAME}';")

    if [ -z "$char_guid" ]; then
        print_error "Character '$CHAR_NAME' not found!"
        return 1
    fi

    print_success "Found: $CHAR_NAME (currently on account: $char_current_acc)"

    echo ""
    echo -e "${WHITE}Available accounts:${NC}"
    mysql_query "$db" "acore_auth" \
        "SELECT id, username FROM account ORDER BY username;" \
        | while IFS=$'\t' read -r id name; do
            echo -e "  ${CYAN}[$id]${NC} $name"
        done

    echo ""
    echo -e "${WHITE}Move $CHAR_NAME to which account? (enter username): ${NC}"
    read -r NEW_ACCOUNT
    NEW_ACCOUNT="${NEW_ACCOUNT^^}"

    local new_acc_id
    new_acc_id=$(mysql_query "$db" "acore_auth" \
        "SELECT id FROM account WHERE username='${NEW_ACCOUNT}';")

    if [ -z "$new_acc_id" ]; then
        print_error "Account '$NEW_ACCOUNT' not found!"
        return 1
    fi

    echo ""
    echo -e "${YELLOW}Move ${WHITE}${CHAR_NAME}${YELLOW} from ${WHITE}${char_current_acc}${YELLOW} to ${WHITE}${NEW_ACCOUNT}${YELLOW}?${NC}"
    echo -e "${WHITE}Continue? (y/n): ${NC}"
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return 0

    # Backup
    create_backup "$db" "pre_char_move" || return 1

    # Move the character
    mysql_exec "$db" "acore_characters" \
        "UPDATE characters SET account=${new_acc_id} WHERE guid=${char_guid};"

    print_success "Done! $CHAR_NAME has been moved to account $NEW_ACCOUNT"
    print_info "Log in with the $NEW_ACCOUNT account to find your character!"
    press_enter
}

# ─────────────────────────────────────────
# FEATURE 5: Restore from backup
# ─────────────────────────────────────────
restore_from_backup() {
    print_step "💾 Restore From Backup"

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR")" ]; then
        print_warning "No backups found in $BACKUP_DIR"
        press_enter
        return 0
    fi

    echo ""
    echo -e "${WHITE}Available backups:${NC}"
    local i=1
    declare -a backup_files
    while IFS= read -r -d $'\0' file; do
        backup_files+=("$file")
        local size
        size=$(du -sh "$file" | cut -f1)
        local fname
        fname=$(basename "$file")
        echo -e "  ${CYAN}[$i]${NC} $fname ($size)"
        i=$((i + 1))
    done < <(find "$BACKUP_DIR" -name "*.sql" -print0 | sort -z)

    echo ""
    echo -e "${WHITE}Which backup? (number): ${NC}"
    read -r backup_choice
    local selected_file="${backup_files[$((backup_choice - 1))]}"

    if [ -z "$selected_file" ] || [ ! -f "$selected_file" ]; then
        print_error "Invalid selection"
        return 1
    fi

    echo ""
    echo -e "${WHITE}Restore to which server?${NC}"
    echo -e "  1) Standard WoW ($STANDARD_DIR)"
    echo -e "  2) NPCBots WoW ($NPCBOTS_DIR)"
    echo -e "${WHITE}Choice (1-2): ${NC}"
    read -r srv_choice

    case "$srv_choice" in
        1) SRV_DIR="$STANDARD_DIR"; SRV_NAME="Standard WoW" ;;
        2) SRV_DIR="$NPCBOTS_DIR";  SRV_NAME="NPCBots WoW" ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac

    echo ""
    print_warning "This will OVERWRITE all data on $SRV_NAME with the backup!"
    echo -e "${WHITE}Are you absolutely sure? Type RESTORE to confirm: ${NC}"
    read -r confirm
    [ "$confirm" = "RESTORE" ] || { print_info "Cancelled."; return 0; }

    if ! is_server_running "$SRV_DIR"; then
        start_server "$SRV_DIR" "$SRV_NAME" || return 1
    fi

    local db
    db=$(get_db_container "$SRV_DIR")

    print_info "Restoring backup..."
    docker exec -i "$db" mysql -uroot -ppassword \
        < "$selected_file" 2>/dev/null

    print_success "Backup restored successfully!"
    press_enter
}

# ─────────────────────────────────────────
# MAIN MENU
# ─────────────────────────────────────────
main_menu() {
    while true; do
        print_header

        echo -e "${WHITE}${BOLD}What would you like to do?${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC} 📋 List all accounts & characters"
        echo -e "  ${CYAN}2)${NC} 🔄 Migrate full account between servers"
        echo -e "  ${CYAN}3)${NC} 👤 Copy single character between servers"
        echo -e "  ${CYAN}4)${NC} 🔀 Move character between accounts (same server)"
        echo -e "  ${CYAN}5)${NC} 💾 Restore from backup"
        echo -e "  ${CYAN}6)${NC} 🚪 Exit"
        echo ""
        echo -e "${WHITE}Choice (1-6): ${NC}"
        read -r choice

        case "$choice" in
            1)
                echo ""
                echo -e "${WHITE}Which server?${NC}"
                echo -e "  1) Standard WoW"
                echo -e "  2) NPCBots WoW"
                echo -e "${WHITE}Choice: ${NC}"
                read -r srv
                case "$srv" in
                    1) list_accounts_and_characters "$STANDARD_DIR" "Standard WoW" ;;
                    2) list_accounts_and_characters "$NPCBOTS_DIR" "NPCBots WoW" ;;
                    *) print_error "Invalid" ;;
                esac
                ;;
            2) migrate_full_account ;;
            3) copy_single_character ;;
            4) move_character_between_accounts ;;
            5) restore_from_backup ;;
            6)
                echo ""
                echo -e "${GREEN}Goodbye! May your characters travel safely. ⚔️${NC}"
                echo ""
                exit 0
                ;;
            *)
                print_error "Invalid choice — please enter 1-6"
                sleep 1
                ;;
        esac
    done
}

# ─────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────

# Check Docker is available
if ! command -v docker &>/dev/null; then
    echo -e "${RED}❌ Docker not found. Are you in Desktop Mode?${NC}"
    exit 1
fi

if ! docker ps &>/dev/null 2>&1; then
    if sudo docker ps &>/dev/null 2>&1; then
        function docker() { sudo docker "$@"; }
        export -f docker 2>/dev/null || true
    else
        echo -e "${RED}❌ Docker is not running. Try rebooting.${NC}"
        exit 1
    fi
fi

main_menu
