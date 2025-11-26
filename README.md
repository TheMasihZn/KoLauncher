# READ OR LEAVE:

#### 1) remind me ANY TIME you see a RemindMe file extension 
* (remind me to make a Remind-Me-If-its-still-not-done-Page functionality)
#### 2) If you found even one small bug, tell me 
* (remind me to design a bullshit free bug report)
#### 3) contrary to what my professors think, I AM a person with a LIFE!! 
* So if something isn't done, Remind me or do it yourself!!
#### 4) This is for my personal use
* if anyone else wanted to use it, ask for help. I'll update the readme.
#### 5) I intend to do everything as simple as possible for me and my goals:
1) VibeCoding,
2) unconventional/multilingual but intuitive namings,
3) hard-to-read but efficient code,
4) easy-to-read but inefficient code,
5) and anything I want to do so if you have any problems,
6) you are not my targe audience,
7) so please don't install or uninstall everything and move on with your life.

The wrest is ai-generated tl;dr good luck reading it!!! 
# KoLauncher / KOReader Plugin Playground

Overview
This repository contains:
- A compiled snapshot of KOReader under compiled/koreader.
- A custom KOReader plugin under mine/RandEst.koplugin (Lua + shell script) called "Est." that runs a small Bash script (rand.sh) to select a row from a CSV and display it in KOReader.
- A Windows batch script (intellijRunConfiguration.bat) intended to deploy a koreader/ folder to a connected Kindle over USB.

The primary purpose is to experiment with KOReader and a custom plugin, and to sync a KOReader build to a Kindle device for testing.


Tech stack
- Languages: Lua (KOReader and plugin), Bash (rand.sh), Windows Batch (deployment script).
- Framework/runtime: KOReader (embedded Lua runtime on e-readers).
- Package manager: none used in this repository.
- Target device: Kindle (or other Linux-based e-readers supported by KOReader).


Project structure
- compiled/ — prebuilt KOReader tree (apps, plugins, resources, etc.).
  - compiled/koreader — KOReader files to place on the device.
- mine/RandEst.koplugin — custom plugin code.
  - main.lua — plugin entry point and KOReader UI bindings.
  - _meta.lua — plugin metadata (name, description).
  - rand.sh — Bash script invoked by the plugin; prints selected CSV row.
  - source.csv — default data file consumed by rand.sh.
- intellijRunConfiguration.bat — Windows deployment helper (copies koreader/ to Kindle drive).


Requirements
- Windows (for the provided deployment script) with PowerShell and Robocopy available.
- A Kindle (or compatible device) mounted as a Windows drive.
- KOReader file tree ready to deploy (see Setup). The compiled snapshot is under compiled/koreader.
- For the plugin’s shell script on-device: a POSIX shell environment with awk, head, tr, and core utilities (KOReader packages for Kindle typically provide a BusyBox shell; awk may be available as busybox awk).


Setup and run
There are two parts to set up: KOReader itself and the custom plugin.

1) Prepare the KOReader directory
- Destination on device: <KindleDrive>\koreader (root of KOReader installation on the Kindle USB storage).
- This repo’s KOReader files are in compiled/koreader.
- You need a koreader directory at the repository root if you want to use the provided batch script as-is.

Options:
- Option A (recommended): Manually deploy compiled/koreader
  1. Connect the Kindle; note its drive letter (e.g., K:).
  2. Copy the contents of compiled/koreader to K:\koreader.

- Option B (use the batch script): Create a koreader directory at repo root
  1. Create a directory at the project root named koreader and copy the contents of compiled/koreader into it.
  2. Run intellijRunConfiguration.bat. It will attempt to auto-detect the Kindle drive by label "Kindle"; otherwise it will prompt for the drive letter.

NOTE: The batch script expects SRC=%SCRIPT_DIR%koreader. Currently, the repository stores KOReader under compiled/koreader. Either adjust the script locally, or create the koreader folder as described above. TODO: Decide whether to update the script or relocate compiled/koreader to koreader in VCS.

2) Install the custom plugin (RandEst.koplugin)
- Copy the folder mine/RandEst.koplugin to <Device>\koreader\plugins\RandEst.koplugin on the Kindle.
- Ensure rand.sh is executable after copying (on device shell):
  chmod +x /mnt/us/koreader/plugins/RandEst.koplugin/rand.sh
- The plugin also expects a CSV file. By default it uses source.csv shipped alongside rand.sh. You can replace or edit this file as needed.

3) Run on device
- Safely eject the Kindle.
- Launch KOReader on the device.
- In KOReader’s main menu or the document menu, find the Est. / Est entries and choose "Run rand.sh".
- The plugin executes rand.sh synchronously and shows the output in an info message.


How the plugin works
- main.lua
  - Registers a dispatcher action (est_run_script) and adds menu items in both the main menu and document menu.
  - Locates its own plugin directory dynamically to compute the path to rand.sh.
  - Runs rand.sh via sh and captures stdout/stderr; displays success or failure text in an InfoMessage.
- _meta.lua provides plugin name and localized description.
- rand.sh
  - Generates a pseudo-random index, selects the corresponding row from a CSV, and prints each column on its own line.
  - Input CSV selection precedence:
    1) First positional argument (CSV file path)
    2) CSV_FILE environment variable
    3) source.csv located next to rand.sh


Commands and scripts
- Deploy KOReader snapshot to Kindle (Windows):
  intellijRunConfiguration.bat [DriveLetter]
  Examples:
  - intellijRunConfiguration.bat           (auto-detect by volume label "Kindle")
  - intellijRunConfiguration.bat K         (use K:)
  - intellijRunConfiguration.bat K:        (use K:)

- Run the shell script locally (Linux/macOS or WSL):
  cd mine/RandEst.koplugin
  chmod +x rand.sh
  ./rand.sh                 # uses source.csv next to the script
  CSV_FILE=path/to/your.csv ./rand.sh
  ./rand.sh path/to/your.csv

Environment variables
- CSV_FILE: Path to a CSV file for rand.sh to read instead of the default source.csv.


Entry points
- KOReader runtime: compiled/koreader (top-level koreader directory on the device).
- Plugin entry: mine/RandEst.koplugin/main.lua (registered by KOReader when placed under koreader/plugins on the device).
- Script entry: mine/RandEst.koplugin/rand.sh (invoked by the plugin, or manually on a POSIX system).
- Deployment entry: intellijRunConfiguration.bat (expects a koreader directory at repository root).


Testing
- Automated tests: none in this repository. TODO: Add unit tests for Lua components (where practical) and shell script validation.
- Manual testing suggestions:
  1) On desktop: run rand.sh with a known small CSV and confirm output format (one column per line). Try with missing file to confirm error messages.
  2) On device: install the plugin, open KOReader, run the menu entry, and verify output. Replace source.csv to ensure the script reads the correct file.


Known limitations / TODOs
- The deployment script expects a koreader folder at repo root; repository currently stores KOReader under compiled/koreader. TODO: unify layout or update script to point to compiled/koreader.
- License file is missing. TODO: add LICENSE and clarify KOReader compiled snapshot licensing compliance and attribution.
- No automated tests. TODO: add tests or CI for the plugin and script where feasible.
- The bash script relies on awk, head, tr. Confirm availability on target devices or bundle minimal dependencies.


License
No explicit license is included in this repository. TODO: Add a LICENSE file. Note that KOReader files are subject to their respective licenses; if you distribute or modify them, ensure compliance and include required notices.
