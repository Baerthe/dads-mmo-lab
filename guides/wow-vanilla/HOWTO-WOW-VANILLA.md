# HOWTO — Vanilla WoW on Steam Deck

*Dad's MMO Lab — beginner-friendly install guide*

*Companion to the YouTube video walkthrough.*

---

## What you're about to do

You're going to install a **complete, offline World of Warcraft Vanilla (1.12.1) server** on your Steam Deck. With AI players. Compiled from source.

When this is done, you'll be able to:

- Boot up your Deck
- Launch your private server from Gaming Mode
- Log into Stormwind, Ironforge, Orgrimmar, Undercity — wherever
- Find AI players already roaming the world, leveling, forming parties
- Group up with them, run dungeons, level up at your own pace
- Auctions in the AH actually have items on them (AI plays the market too)

**No internet required after install.** No subscription. No server downtime. Your Azeroth, your rules.

This is the original 2004 WoW — 60 level cap, 40-man raids, no flying mounts, no Death Knights, no Outland. Pure Vanilla.

---

## ⚠️ The honest big warning — this takes 3-5 hours

I want to be straight with you up front.

This installer **compiles the server from source code on your Steam Deck.** That's 2-4 hours of just sitting and compiling C++ code. Plus another 30-40 minutes of extracting game world data from your WoW client. Plus another 30 minutes generating pathfinding data so the AI players can navigate without bumping into walls.

**Total time: 3-5 hours of mostly hands-off waiting.**

Plug your Deck in. Set it on a flat hard surface. The fan will run loud. Walk away and watch a movie. Come back to a finished server.

**🔜 Coming soon:** Dad's MMO Lab is building pre-built Docker images that will skip the entire compile step — installing in about 5 minutes instead of 3-5 hours. When that's ready, there'll be a separate `install-wow-vanilla-fast.sh` for that path. **This installer is for folks who can't wait** for that, or who want the satisfaction of compiling their own server from source.

If you'd rather wait for the fast version, watch the Lab's GitHub and YouTube channel for the announcement.

If you're ready to bake your Deck for Azeroth tonight — read on.

---

## ⚠️ The OTHER honest warning — you need a real WoW client

You need the **Vanilla WoW 1.12.1 client** (build 5875). The server alone is not enough.

The current Battle.net "WoW Classic" client **doesn't work** — that's the 2019 re-release built on the modern engine. You need the genuine 2006 client.

**Where you get the client is up to you.** I can't legally point you to a source. The classic emulator community has been preserving these clients for nearly two decades. There are forums, Discord servers, and archives. Find a community, ask around. Just don't ask in YouTube comments because I can't legally answer.

### What a valid client looks like

✅ Folder ~5 GB total
✅ Contains `WoW.exe` (capital W's vary — `wow.exe` is also fine)
✅ Contains a `Data/` folder
✅ **CRITICAL:** Contains `Data/dbc.MPQ` — this file is required for the installer
✅ Has 10-14 `.MPQ` files in `Data/`

### Red flags — wrong version

❌ Bigger than 10 GB total (probably modern Classic)
❌ Has folders like `_classic_`, `_retail_`, or `BackgroundDownloader.exe` dated after 2010
❌ Less than 5 `.MPQ` files in `Data/`
❌ No `dbc.MPQ` file (some heavily-stripped repacks remove it — those won't work)

**The installer will validate this for you BEFORE starting the 3-hour compile.** So even if you're unsure, the installer will catch a bad client up front and tell you instead of wasting your night.

---

## What else you need

1. ✅ Steam Deck running Desktop Mode (Power → Switch to Desktop)
2. ✅ Your Vanilla 1.12.1 WoW client folder, somewhere accessible
3. ✅ At least **20 GB free disk space** (the compile produces 5+ GB of artifacts)
4. ✅ Internet connection (downloads several GB of build dependencies)
5. ✅ **Deck plugged into power** — this is non-negotiable for a 3-hour compile
6. ✅ A flat hard surface for the Deck (fan needs airflow)
7. ✅ ~3-5 hours of mostly-uninterrupted time

You don't need to install Docker or any other dependencies. The installer handles that.

---

## ⭐ Step 1 — Get the installer onto your Steam Deck

Download `install-wow-vanilla.sh` from the Lab's GitHub or the YouTube video description.

By default on Steam Deck, it lands in `~/Downloads`. That's fine — leave it there or move it wherever you want. The location doesn't matter.

---

## ⭐ Step 2 — Know where your WoW client is

Before running anything, **find your WoW client folder and remember the exact path.** The installer will ask for it.

The path is the folder that contains `WoW.exe` AND a `Data/` subfolder. Common examples:

- `/home/deck/Games/VanillaWow`
- `/home/deck/Games/World Of Warcraft Classic` *(note: spaces in path are fine)*
- `/run/media/deck/SD-Card/WoW-Vanilla` *(if on SD card)*

If you put the WoW folder in a location with spaces in the name, that's fine — the installer handles spaces. Just type the path correctly when asked.

**Don't put your WoW client on a slow USB drive.** SSD or fast SD card only. Extraction reads through every MPQ.

---

## ⭐ Step 3 — Open Konsole (terminal)

In Desktop Mode, find **Konsole** (it's KDE's terminal):

- **Easiest:** Press the Steam button → Application Launcher → System → Konsole
- **Or:** Click the K menu (bottom-left) → search "konsole" → click it

You should see a black terminal window with a `$` prompt. **Don't close this for the next 3-5 hours.**

---

## ⭐ Step 4 — Make the installer executable

In Konsole, type (or paste):

```bash
chmod +x ~/Downloads/install-wow-vanilla.sh
```

Press Enter. Nothing visible happens. That's correct — `chmod` runs silently.

---

## ⭐ Step 5 — Run the installer

```bash
~/Downloads/install-wow-vanilla.sh
```

Press Enter.

You'll see a welcome screen with all the warnings I just gave you (in more compact form), plus an honest time estimate. **Read it carefully.** When you're ready, type `y` and press Enter.

---

## ⭐ Step 6 — Validation phase (~30 seconds)

The installer first does a bunch of fast checks **before committing to anything slow**:

- Verifies your Steam Deck setup
- Asks you for your WoW client folder path
- Validates the client folder has the right files (especially `dbc.MPQ`)
- Checks you have enough disk space
- Checks Docker

If anything looks wrong, **it stops here and tells you exactly what's missing** before wasting your time on a 3-hour compile. This is a real safety net.

**When prompted for client path:** type the full path. Tab completion works in Konsole, so you can type `/home/deck/G` and press Tab to autocomplete.

If your client passes validation, you'll see:
```
✅ WoW client validated: /home/deck/Games/...
✅ Found 14 .MPQ files including dbc.MPQ
```

---

## ⭐ Step 7 — Pre-compile summary (read carefully)

The installer prints a final summary showing:
- Where the server will live
- Database password it generated
- Where compile logs will go

**This is the last chance to bail before commitment.** If anything looks wrong, type `n` and the installer exits cleanly. If you're good, type `y`.

---

## ⭐ Step 8 — Compile time (2-4 hours)

Here's the long one. **Plug your Deck in. Flat surface. Walk away.**

You'll see Docker building the server image. The output looks like:
```
Step 4/17 : RUN apt-get install ...
Step 5/17 : WORKDIR /src
Step 6/17 : RUN git clone ...
...
[ 23%] Building CXX object src/game/Server/...
[ 24%] Building CXX object src/game/...
```

The Deck's fan will get LOUD. **That's normal.** The CPU is at 100% on 2 cores for hours.

**The percentage in the brackets `[ XX%]` is your progress meter.** Going from 0% to 100% takes the full 2-4 hours.

### What if it crashes mid-compile?

Honestly — it shouldn't. The installer was hardened against the known compile failures (gcc bugs, missing dependencies, certificate issues). But if it does fail:

- The full build log is at `/tmp/wow-vanilla-build.log`
- Most failures will resume from where they failed if you re-run the installer (Docker caches successful layers)
- Drop a screenshot of the error in the YouTube comments — these get fixed and the installer iterates

---

## ⭐ Step 9 — Extraction phase (~30 minutes)

When the compile finishes, the installer immediately starts extracting game world data from your WoW client.

You'll see:
```
=== Extraction starting at ... ===
Working directory: /client
=== Running ExtractResources.sh a (non-interactive, all data) ===
Current Settings: Extract DBCs/maps: 1, Extract vmaps: 1, Extract mmaps: 1
Start extracting MaNGOS data: DBCs/maps 1, vmaps 1, mmaps 1
...
Extract Azeroth (1/44)
Extract Kalimdor (2/44)
Extract test (3/44)
...
```

This takes about 15-20 minutes. You're extracting ~3000 map tiles, 158 DBC files, and ~5000 vmap files from your client.

**Important detail:** The installer writes temporary folders (`maps/`, `vmaps/`, `Buildings/`) **inside your WoW client folder** during extraction. When it's done, it moves them OUT into the server's data folder. **If extraction is interrupted, you might find these temp folders in your client folder afterward — they're safe to delete.**

---

## ⭐ Step 10 — Pathfinding generation (~30 minutes)

Right after extraction, the installer generates "mmaps" — pathfinding mesh files. These are what let the AI bots navigate the world without bumping into walls or getting stuck on stairs.

You'll see:
```
[Map 000] Building tile [39,49] (561 / 687)
[Map 000] Building tile [39,50] (562 / 687)
...
Map [000] is done!
[Map 001] Building tile [12,28]
```

Map 0 is Eastern Kingdoms. Map 1 is Kalimdor. These are the biggest two and take most of the time. Smaller dungeon maps fly through.

**Mmaps are required.** Without them, the server boots but immediately crashes when bots try to generate travel routes. That's why we generate them now instead of skipping.

---

## ⭐ Step 11 — Database setup (~5 minutes)

Once mmaps are done, the installer:
1. Starts the MariaDB container
2. Creates 4 databases (mangos, realmd, characters, logs)
3. Creates the `mangos` database user with grants
4. Imports schema files
5. Imports world content (17K items, 10K creatures, 4K quests)
6. Applies 300+ content updates
7. Applies ACID creature AI scripts
8. Applies core schema updates
9. Imports Playerbots SQL (23 tables for the AI players)
10. Verifies table counts

This is SUPER fast on Steam Deck SSD — the whole thing takes under 5 minutes. You'll see a parade of "X applied, Y failed" messages. **Some failures are expected and harmless** (mostly version-tracking columns that don't exist on fresh installs). What matters is the final verification:

```
✅ Database setup looks healthy!
  item_template rows: 17718 (expect ~17,718)
  ai_playerbot_* tables: 12 (expect ~12)
```

---

## ⭐ Step 12 — Server start (~1-2 minutes)

The installer brings up `mangosd` (world server) and `realmd` (login server). It waits for the magic phrase in the logs:

```
CMANGOS: World initialized
```

When you see that, **the hard part is done.** Your Vanilla WoW server is running.

---

## ⭐ Step 13 — Account creation

The installer creates a default account: **`player`** / **`player`** (GM level 3 — you're an admin).

The account is created by writing directly to the realmd database. This is more reliable than fighting with mangosd's console — we learned this the hard way.

If account creation fails for some reason, the installer prints manual instructions.

---

## ⭐ Step 14 — Realmlist auto-config

The installer writes `set realmlist 127.0.0.1` to your client's `realmlist.wtf` file, then locks it with `chmod 444` so the client can't overwrite it.

**If this auto-write fails** (your client folder might have unusual permissions), the installer tells you. Just edit `realmlist.wtf` manually as described in the completion screen.

---

## ⭐ Step 15 — DONE!

You'll see the completion banner:

```
╔══════════════════════════════════════════════════╗
║         🎉 VANILLA WOW INSTALLED! 🎉              ║
╚══════════════════════════════════════════════════╝

You compiled CMaNGOS Classic from source on your Steam Deck.
That's real engineering work. Welcome to a club of one.
```

The completion screen shows your "Next Steps" — adding the launcher to Steam and connecting your WoW client.

---

## ⭐ Step 16 — Steam Gaming Mode setup (5 minutes)

Two non-Steam games to add. Stay in Desktop Mode for this.

### Add 1: The server launcher

1. Open Steam in Desktop Mode
2. Games → Add a Non-Steam Game to My Library
3. Click **Browse**
4. Navigate to `/usr/bin/konsole`, select it, add it
5. Find it in your library → right-click → Properties
6. Rename to: **`Vanilla WoW Server`**
7. Launch Options: `--hold -e bash ~/wow-vanilla-launcher.sh`
8. Compatibility tab: **leave default** (do NOT force Proton — this is a Linux script)

### Add 2: The WoW client

1. Games → Add a Non-Steam Game to My Library again
2. Click Browse, navigate to your WoW folder
3. Select `WoW.exe`, add it
4. Find it in your library → right-click → Properties
5. Rename to: **`Vanilla WoW`**
6. Compatibility tab: ☑ "Force the use of..." → select **GE-Proton** (latest)
   - If you don't see GE-Proton, install **ProtonUp-Qt** first (from Discover), then add GE-Proton through there

### Switch to Gaming Mode

Power button → Switch to Gaming Mode.

---

## ⭐ Step 17 — PLAY

In Gaming Mode:

1. Find **Vanilla WoW Server** in your library → Launch
2. Konsole opens, runs the launcher
3. Server boots up (~30-60 sec since DB is already populated)
4. You'll see: **`🎉 AZEROTH IS READY!`**
5. **Don't close that window** — it keeps the server running
6. Press the Steam button → go back to your library
7. Find **Vanilla WoW** → Launch
8. WoW client opens under Proton
9. Login screen appears
10. **Username: `player`** / **Password: `player`**
11. You're in.
12. Make a character. Roll whatever class speaks to you. Don't overthink it.
13. Click Enter World
14. **Welcome to Azeroth.**

---

## What playing looks like

For the first **5-10 minutes**, the world may seem quiet. **Playerbots is generating its random bot characters in the background.** Be patient.

After that, you'll start seeing:
- AI players running around starting zones
- Bots chatting in `/say` and `/yell`
- AI players forming parties, doing quests
- Auction house listings appearing (AHBot is populating it)
- Bots in guild chat (yes, you can get **invited to a bot guild**)

Some bot quirks:
- They sometimes path awkwardly (mmaps help but aren't perfect)
- They occasionally cast weird spells (Playerbots is amazing but it's not Blizzard polished)
- They WILL be in your starting zones — you might see 5 hunters all training pets at the same time. That's the lab in motion.

---

## Shutting down cleanly

When you're done playing for the night, **just close WoW.** The launcher detects the WoW process ending and shuts down the server automatically.

If for some reason you need to stop the server manually from Desktop Mode:

```bash
cd ~/wow-vanilla-server
docker compose stop
```

To start it again:

```bash
cd ~/wow-vanilla-server
docker compose up -d
```

Your character, items, gold, level — all persist between sessions. Docker volumes preserve everything.

---

## Troubleshooting

### "Compile failed at X%"

Check `/tmp/wow-vanilla-build.log` for the actual error. Most compile failures are dependency-related and have been pre-handled by v1.1.0. If you hit a new one, share the last 50 lines of the log in YouTube comments.

### "Extraction had errors"

Almost always means the client is missing files. If you have `Data/dbc.MPQ`, the rest should work. Some warnings during extraction are normal — actual errors will stop the process.

### "mangosd is in a restart loop"

Means a step in DB setup didn't complete. Check the verification output for "item_template rows" — should be ~17,000. If it's much lower, something failed mid-import. Re-running the installer (and saying yes to remove existing install) usually fixes it.

### "Can't connect — wrong password"

The `player/player` account uses CMaNGOS's SHA1 hash format. If login fails, the account exists but the hash is wrong. Recreate by attaching to the server:

```bash
docker attach vanilla-mangosd
```
Type: `account create player2 password` (use a different name to avoid collision)
**Exit with Ctrl+P then Ctrl+Q — NEVER Ctrl+C (that kills the server!)**

### Bots aren't appearing

Give it 5-10 minutes after first login. Playerbots generates random bot characters and gear on demand. They start appearing as you walk into populated zones.

### Server very slow on first launch

First launch loads all map files into memory. Walking into a new zone for the first time is also slow (it loads that zone's data). Subsequent visits are fast.

---

## Mental model — what's running on your Deck

Three Docker containers:

- **vanilla-db** — MariaDB, holds your world, characters, accounts, logs
- **vanilla-realmd** — Login server (port 3724), the gateway
- **vanilla-mangosd** — World server (port 8085), the actual game world

Plus your WoW client running under Proton. That's the whole stack.

When you launch the server, all three containers start. When you close WoW, the launcher stops them. Clean.

---

## What's next from the Lab

- **🔜 Coming soon:** Pre-built Docker images so future installs are 5-min pulls instead of 3-hour compiles
- **Other expansions:** A `install-wow-tbc.sh` is on the roadmap (Burning Crusade with bots)
- **Other MMOs:** EverQuest, RuneScape, Ultima Online, Phantasy Star Online, and more — see the Lab's full game list

Subscribe to the channel, watch GitHub for the Docker image release, and **show off your bot-filled Azeroth**.

---

## A note from the Lab

Compiling CMaNGOS from source on a Steam Deck is **real engineering work.** A handful of people have ever done it. Compiling it WITH Playerbots is even rarer — there's no pre-built public Linux Docker image for that combination as of right now.

You just joined a very small club. Take a screenshot of your character standing in Stormwind. **That's the brand. That's the Lab. That's what we built.**

Welcome to Azeroth, dad. Go save the world. ⚔️🏰🤖

---

*Companion HOWTO for `install-wow-vanilla.sh` v1.1.0.*
*Watch the video guide at youtube.com/@DadsMmoLab.*
