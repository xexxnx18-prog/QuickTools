#!/usr/bin/env python3
import os
import json
import shutil
import subprocess
import requests
import zipfile
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Tuple

class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    RESET = '\033[0m'

class ServerPanel:
    
    SOFTWARE_APIS = {
        "papermc": {
            "name": "PaperMC",
            "api_url": "https://api.papermc.io/v2/projects/paper",
            "version_url": "https://api.papermc.io/v2/projects/paper/versions/{version}/builds",
            "build_url": "https://api.papermc.io/v2/projects/paper/versions/{version}/builds/{build}",
            "download_pattern": "https://api.papermc.io/v2/projects/paper/versions/{version}/builds/{build}/downloads/{filename}"
        },
        "fabricmc": {
            "name": "FabricMC",
            "api_url": "https://meta.fabricmc.net/v2/versions/loader",
            "version_url": "https://meta.fabricmc.net/v2/versions/loader/{version}",
            "build_url": None,
            "download_pattern": "https://meta.fabricmc.net/v2/versions/loader/{version}/{loader_version}/server/jar"
        },
        "neoforge": {
            "name": "NeoForge",
            "api_url": "https://maven.neoforged.net/api/maven/latest/version/releases/net/neoforged/neoforge",
            "version_url": "https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge",
            "build_url": None,
            "download_pattern": "https://maven.neoforged.net/releases/net/neoforged/neoforge/{version}/neoforge-{version}-installer.jar"
        },
        "vanilla": {
            "name": "Vanilla",
            "api_url": "https://launchermeta.mojang.com/mc/game/version_manifest.json",
            "version_url": None,
            "download_pattern": None
        }
    }
    
    def __init__(self, server_dir):
        self.server_dir = Path(server_dir)
        self.config_file = self.server_dir / "panel_config.json"
        self.config = self.load_config()
        self.server_properties = self.server_dir / "server.properties"
        self.whitelist_file = self.server_dir / "whitelist.json"
        self.banned_ips_file = self.server_dir / "banned-ips.json"
        self.ops_file = self.server_dir / "ops.json"
        self.server_jar = self.server_dir / "server.jar"
        
    def load_config(self):
        if self.config_file.exists():
            with open(self.config_file, 'r') as f:
                return json.load(f)
        return self.default_config()
    
    def save_config(self):
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f, indent=4)
    
    def default_config(self):
        return {
            "server_name": "QuickTools Minecraft Server",
            "server_description": "A Minecraft Server",
            "description_color": "GREEN",
            "gamemode": "survival",
            "difficulty": "easy",
            "hardcore": False,
            "software": "papermc",
            "software_version": "latest",
            "world_type": "default",
            "allocated_ram": "1G",
            "block_cracked": True,
            "whitelist_enabled": False,
            "max_players": 20,
            "view_distance": 10,
            "simulation_distance": 10,
            "pvp": True,
            "allow_nether": True,
            "allow_flight": False,
            "spawn_protection": 16,
            "enable_command_block": False,
            "allow_end": True,
            "port": 25565,
            "auto_update": False,
            "last_update_check": None
        }
    
    def print_colored(self, text, color):
        print(f"{color}{text}{Colors.RESET}")
    
    def show_banner(self):
        banner = f"""
{Colors.CYAN}+====================================================+
{Colors.CYAN}|{Colors.YELLOW}          QuickTools Server Control Panel          {Colors.CYAN}|
{Colors.CYAN}+====================================================+
{Colors.CYAN}|{Colors.GREEN} Server: {self.config['server_name'][:40]:<40} {Colors.CYAN}|
{Colors.CYAN}|{Colors.WHITE} Software: {self.config['software']:<38} {Colors.CYAN}|
{Colors.CYAN}|{Colors.MAGENTA} Gamemode: {self.config['gamemode']:<37} {Colors.CYAN}|
{Colors.CYAN}+====================================================+
{Colors.RESET}"""
        print(banner)
    
    def main_menu(self):
        if self.config.get("auto_update") and self.server_jar.exists():
            self.check_and_auto_update()
        
        while True:
            os.system('clear')
            self.show_banner()
            
            menu_items = [
                ("Server Name & Description", self.change_server_info),
                ("Gameplay Settings", self.gameplay_settings),
                ("Software Selection", self.software_selection),
                ("World Management", self.world_management),
                ("Mods & Plugins", self.mods_plugins_menu),
                ("Performance Settings", self.performance_settings),
                ("Network & Security", self.network_settings),
                ("Player Management", self.player_management),
                ("Update Server Software", self.update_server_software),
                ("Auto-Update Toggle", self.toggle_auto_update),
                ("Start Server", self.start_server),
                ("Exit Panel", None)
            ]
            
            for i, (name, func) in enumerate(menu_items, 1):
                if name == "Exit Panel":
                    print(f"\n{Colors.RED}  {i}. {name}{Colors.RESET}")
                elif name == "Auto-Update Toggle":
                    status = "ON" if self.config.get("auto_update") else "OFF"
                    print(f"  {Colors.BOLD}{i}.{Colors.RESET} {name} [{Colors.GREEN if status == 'ON' else Colors.RED}{status}{Colors.RESET}]")
                else:
                    print(f"  {Colors.BOLD}{i}.{Colors.RESET} {name}")
            
            choice = input(f"\n{Colors.CYAN}Select option (1-{len(menu_items)}): {Colors.RESET}")
            
            if choice == str(len(menu_items)):
                print(f"{Colors.YELLOW}Exiting panel...{Colors.RESET}")
                break
            elif choice.isdigit() and 1 <= int(choice) <= len(menu_items) - 1:
                menu_items[int(choice) - 1][1]()
            else:
                print(f"{Colors.RED}Invalid choice!{Colors.RESET}")
                input("Press Enter to continue...")
    
    def fetch_latest_version(self, software: str) -> Optional[str]:
        if software not in self.SOFTWARE_APIS:
            return None
        
        api = self.SOFTWARE_APIS[software]
        try:
            if software == "papermc":
                resp = requests.get(api["api_url"])
                versions = resp.json().get("versions", [])
                return versions[-1] if versions else None
            
            elif software == "fabricmc":
                resp = requests.get(api["api_url"])
                data = resp.json()
                stable = [v for v in data if v.get("stable")]
                return stable[-1]["version"] if stable else None
            
            elif software == "neoforge":
                resp = requests.get(api["api_url"])
                return resp.text.strip()
            
            elif software == "vanilla":
                resp = requests.get(api["api_url"])
                manifest = resp.json()
                latest = manifest.get("latest", {}).get("release")
                return latest
        
        except Exception as e:
            self.print_colored(f"API error: {e}", Colors.RED)
            return None
    
    def get_download_url(self, software: str, version: str) -> Optional[str]:
        api = self.SOFTWARE_APIS[software]
        
        try:
            if software == "papermc":
                resp = requests.get(api["version_url"].format(version=version))
                builds = resp.json().get("builds", [])
                if not builds:
                    return None
                latest_build = max(b["build"] for b in builds)
                build_resp = requests.get(api["build_url"].format(version=version, build=latest_build))
                build_data = build_resp.json()
                filename = build_data["downloads"]["application"]["name"]
                return api["download_pattern"].format(version=version, build=latest_build, filename=filename)
            
            elif software == "fabricmc":
                resp = requests.get(api["version_url"].format(version=version))
                loaders = resp.json()
                if not loaders:
                    return None
                latest_loader = loaders[0]["loader"]["version"]
                return api["download_pattern"].format(version=version, loader_version=latest_loader)
            
            elif software == "neoforge":
                return api["download_pattern"].format(version=version)
            
            elif software == "vanilla":
                resp = requests.get(api["api_url"])
                manifest = resp.json()
                for v in manifest["versions"]:
                    if v["id"] == version:
                        v_resp = requests.get(v["url"])
                        v_data = v_resp.json()
                        return v_data["downloads"]["server"]["url"]
                return None
        
        except Exception as e:
            self.print_colored(f"Download URL error: {e}", Colors.RED)
            return None
    
    def download_jar(self, url: str, filename: str = "server.jar"):
        try:
            self.print_colored("Downloading server jar...", Colors.YELLOW)
            response = requests.get(url, stream=True)
            response.raise_for_status()
            
            total_size = int(response.headers.get('content-length', 0))
            block_size = 8192
            downloaded = 0
            
            temp_path = self.server_dir / (filename + ".tmp")
            with open(temp_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=block_size):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        if total_size > 0:
                            percent = (downloaded / total_size) * 100
                            bar_length = 40
                            filled = int(bar_length * downloaded / total_size)
                            bar = '#' * filled + '-' * (bar_length - filled)
                            print(f'\r[PROGRESS] |{bar}| {percent:.1f}%', end='')
            
            print()
            target = self.server_dir / filename
            if target.exists():
                target.unlink()
            temp_path.rename(target)
            self.print_colored("Download complete!", Colors.GREEN)
            return True
        except Exception as e:
            self.print_colored(f"Download failed: {e}", Colors.RED)
            return False
    
    def check_and_auto_update(self):
        if not self.config.get("auto_update"):
            return
        
        last_check = self.config.get("last_update_check")
        if last_check:
            last = datetime.fromisoformat(last_check)
            if (datetime.now() - last).total_seconds() < 86400:  # once per day
                return
        
        self.print_colored("Auto-update check...", Colors.YELLOW)
        latest = self.fetch_latest_version(self.config['software'])
        if latest and latest != self.config.get('software_version'):
            print(f"New version available: {latest}")
            self.perform_update(latest)
        
        self.config['last_update_check'] = datetime.now().isoformat()
        self.save_config()
    
    def perform_update(self, version: str):
        software = self.config['software']
        url = self.get_download_url(software, version)
        if url:
            if self.download_jar(url):
                self.config['software_version'] = version
                self.save_config()
                self.print_colored(f"Updated to {software} {version}", Colors.GREEN)
        else:
            self.print_colored("Could not retrieve download URL", Colors.RED)
    
    def toggle_auto_update(self):
        self.config['auto_update'] = not self.config.get('auto_update', False)
        status = "enabled" if self.config['auto_update'] else "disabled"
        self.print_colored(f"Auto-update {status}", Colors.YELLOW)
        self.save_config()
        input("Press Enter to continue...")
    
    def update_server_software(self):
        os.system('clear')
        self.print_colored("=== Update Server Software ===", Colors.CYAN)
        
        software = self.config['software']
        current_version = self.config.get('software_version', 'unknown')
        print(f"Current software: {software} ({current_version})")
        
        latest = self.fetch_latest_version(software)
        if not latest:
            self.print_colored("Could not fetch latest version", Colors.RED)
            input("Press Enter...")
            return
        
        print(f"Latest version available: {latest}")
        if latest == current_version:
            self.print_colored("You are already on the latest version.", Colors.GREEN)
        else:
            choice = input("Download and install latest version? (y/n): ").lower()
            if choice == 'y':
                self.perform_update(latest)
        input("Press Enter to continue...")
    
    def change_server_info(self):
        os.system('clear')
        self.print_colored("=== Server Name & Description ===", Colors.CYAN)
        
        print(f"\n{Colors.WHITE}Current Name:{Colors.RESET} {self.config['server_name']}")
        new_name = input(f"{Colors.GREEN}Enter new server name: {Colors.RESET}").strip()
        if new_name:
            self.config['server_name'] = new_name
        
        print(f"\n{Colors.WHITE}Current Description:{Colors.RESET} {self.config['server_description']}")
        new_desc = input(f"{Colors.GREEN}Enter new description: {Colors.RESET}").strip()
        if new_desc:
            self.config['server_description'] = new_desc
        
        print(f"\n{Colors.WHITE}Description Colors:{Colors.RESET}")
        colors = {
            "1": "RED", "2": "GREEN", "3": "YELLOW", "4": "BLUE",
            "5": "MAGENTA", "6": "CYAN", "7": "WHITE"
        }
        
        for key, value in colors.items():
            color_code = getattr(Colors, value)
            print(f"  {key}. {color_code}{value}{Colors.RESET}")
        
        color_choice = input(f"{Colors.GREEN}Select color (1-7): {Colors.RESET}").strip()
        if color_choice in colors:
            self.config['description_color'] = colors[color_choice]
        
        self.save_config()
        self.apply_server_properties()
        self.print_colored("Server info updated!", Colors.GREEN)
        input("Press Enter to continue...")
    
    def gameplay_settings(self):
        os.system('clear')
        self.print_colored("=== Gameplay Settings ===", Colors.CYAN)
        
        print(f"\n{Colors.WHITE}Gameplay Rules:{Colors.RESET}")
        print(f"  1. Gamemode: {Colors.GREEN}{self.config['gamemode']}{Colors.RESET}")
        print(f"  2. Difficulty: {Colors.YELLOW}{self.config['difficulty']}{Colors.RESET}")
        print(f"  3. Hardcore: {Colors.RED if self.config['hardcore'] else Colors.GREEN}{self.config['hardcore']}{Colors.RESET}")
        print(f"  4. PvP: {Colors.RED if self.config['pvp'] else Colors.GREEN}{self.config['pvp']}{Colors.RESET}")
        print(f"  5. Allow Flight: {Colors.GREEN if self.config['allow_flight'] else Colors.RED}{self.config['allow_flight']}{Colors.RESET}")
        print(f"  6. Command Blocks: {Colors.GREEN if self.config['enable_command_block'] else Colors.RED}{self.config['enable_command_block']}{Colors.RESET}")
        print(f"  7. Back to Main Menu")
        
        choice = input(f"\n{Colors.CYAN}Select setting to change: {Colors.RESET}")
        
        if choice == "1":
            print(f"\n{Colors.WHITE}Gamemodes:{Colors.RESET}")
            gamemodes = {"1": "survival", "2": "creative", "3": "adventure", "4": "spectator"}
            for key, value in gamemodes.items():
                print(f"  {key}. {value}")
            gm_choice = input(f"{Colors.GREEN}Select gamemode: {Colors.RESET}")
            if gm_choice in gamemodes:
                self.config['gamemode'] = gamemodes[gm_choice]
        
        elif choice == "2":
            print(f"\n{Colors.WHITE}Difficulties:{Colors.RESET}")
            difficulties = {"1": "peaceful", "2": "easy", "3": "normal", "4": "hard"}
            for key, value in difficulties.items():
                print(f"  {key}. {value}")
            diff_choice = input(f"{Colors.GREEN}Select difficulty: {Colors.RESET}")
            if diff_choice in difficulties:
                self.config['difficulty'] = difficulties[diff_choice]
        
        elif choice == "3":
            self.config['hardcore'] = not self.config['hardcore']
            print(f"Hardcore: {self.config['hardcore']}")
        
        elif choice == "4":
            self.config['pvp'] = not self.config['pvp']
        
        elif choice == "5":
            self.config['allow_flight'] = not self.config['allow_flight']
        
        elif choice == "6":
            self.config['enable_command_block'] = not self.config['enable_command_block']
        
        elif choice == "7":
            return
        
        self.save_config()
        self.apply_server_properties()
        self.gameplay_settings()
    
    def software_selection(self):
        os.system('clear')
        self.print_colored("=== Software Selection ===", Colors.CYAN)
        
        software_options = {
            "1": {"name": "PaperMC", "key": "papermc", "desc": "High performance, plugin support"},
            "2": {"name": "FabricMC", "key": "fabricmc", "desc": "Lightweight, mod support"},
            "3": {"name": "NeoForge", "key": "neoforge", "desc": "Modern modding platform"},
            "4": {"name": "Vanilla", "key": "vanilla", "desc": "Original Minecraft server"},
            "5": {"name": "Purpur", "key": "papermc", "desc": "Fork of Paper with more features"},
            "6": {"name": "Spigot", "key": "papermc", "desc": "Popular plugin server"}
        }
        
        for key, value in software_options.items():
            marker = " [ACTIVE]" if self.config['software'] == value['key'] else ""
            print(f"  {key}. {Colors.BOLD}{value['name']}{Colors.RESET}{Colors.GREEN}{marker}{Colors.RESET}")
            print(f"     {Colors.WHITE}{value['desc']}{Colors.RESET}")
        
        print(f"\n  7. Back to Main Menu")
        
        choice = input(f"\n{Colors.CYAN}Select software: {Colors.RESET}")
        
        if choice in software_options:
            old_software = self.config['software']
            self.config['software'] = software_options[choice]['key']
            if old_software != self.config['software']:
                self.config['software_version'] = None  # reset version
                confirm = input(f"{Colors.YELLOW}Download new server jar? (y/n): {Colors.RESET}")
                if confirm.lower() == 'y':
                    latest = self.fetch_latest_version(self.config['software'])
                    if latest:
                        self.perform_update(latest)
            self.print_colored(f"Selected: {software_options[choice]['name']}", Colors.GREEN)
            self.save_config()
            input("Press Enter to continue...")
            self.software_selection()
        elif choice == "7":
            return
        else:
            self.software_selection()
    
    def world_management(self):
        os.system('clear')
        self.print_colored("=== World Management ===", Colors.CYAN)
        
        world_types = {
            "1": "default",
            "2": "flat",
            "3": "largebiomes",
            "4": "amplified",
            "5": "singlebiome"
        }
        
        print(f"\n{Colors.WHITE}World Type:{Colors.RESET} {Colors.GREEN}{self.config['world_type']}{Colors.RESET}")
        print(f"\n{Colors.BOLD}Available World Types:{Colors.RESET}")
        for key, value in world_types.items():
            print(f"  {key}. {value}")
        
        print(f"\n{Colors.BOLD}World Operations:{Colors.RESET}")
        print(f"  6. Backup Current World")
        print(f"  7. Import World")
        print(f"  8. Reset World")
        print(f"  9. Back to Main Menu")
        
        choice = input(f"\n{Colors.CYAN}Select option: {Colors.RESET}")
        
        if choice in world_types:
            self.config['world_type'] = world_types[choice]
            self.save_config()
            self.print_colored(f"World type set to: {world_types[choice]}", Colors.GREEN)
        
        elif choice == "6":
            self.backup_world()
        
        elif choice == "7":
            self.import_world()
        
        elif choice == "8":
            confirm = input(f"{Colors.RED}Delete current world? (yes/no): {Colors.RESET}")
            if confirm.lower() == "yes":
                world_folders = ["world", "world_nether", "world_the_end"]
                for folder in world_folders:
                    folder_path = self.server_dir / folder
                    if folder_path.exists():
                        shutil.rmtree(folder_path)
                        print(f"Deleted: {folder}")
                self.print_colored("World reset complete", Colors.GREEN)
        
        elif choice == "9":
            return
        
        input("Press Enter to continue...")
        self.world_management()
    
    def backup_world(self):
        backup_dir = self.server_dir / "backups"
        backup_dir.mkdir(exist_ok=True)
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_name = f"world_backup_{timestamp}"
        backup_path = backup_dir / backup_name
        
        world_path = self.server_dir / "world"
        
        if world_path.exists():
            self.print_colored(f"Creating backup: {backup_name}", Colors.YELLOW)
            shutil.make_archive(str(backup_path), 'zip', str(world_path))
            self.print_colored(f"Backup created: {backup_name}.zip", Colors.GREEN)
        else:
            self.print_colored("No world found to backup!", Colors.RED)
    
    def import_world(self):
        print(f"\n{Colors.YELLOW}Import World Options:{Colors.RESET}")
        print("  1. From zip file in server directory")
        print("  2. From external path")
        
        choice = input(f"{Colors.CYAN}Select: {Colors.RESET}")
        
        if choice == "1":
            zip_files = list(self.server_dir.glob("*.zip"))
            if not zip_files:
                print("No zip files found in server directory")
                return
            
            for i, zip_file in enumerate(zip_files, 1):
                print(f"  {i}. {zip_file.name}")
            
            file_choice = input(f"{Colors.GREEN}Select file: {Colors.RESET}")
            if file_choice.isdigit() and 1 <= int(file_choice) <= len(zip_files):
                selected_file = zip_files[int(file_choice) - 1]
                self.extract_world(selected_file)
        
        elif choice == "2":
            path = input(f"{Colors.GREEN}Enter full path to world zip: {Colors.RESET}")
            if os.path.exists(path):
                self.extract_world(Path(path))
    
    def extract_world(self, zip_path):
        world_path = self.server_dir / "world"
        if world_path.exists():
            confirm = input(f"{Colors.RED}World already exists. Overwrite? (yes/no): {Colors.RESET}")
            if confirm.lower() != "yes":
                return
            shutil.rmtree(world_path)
        
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(self.server_dir)
        self.print_colored("World imported successfully!", Colors.GREEN)
    
    def mods_plugins_menu(self):
        os.system('clear')
        self.print_colored("=== Mods & Plugins ===", Colors.CYAN)
        
        print(f"\n{Colors.BOLD}Current Software:{Colors.RESET} {Colors.GREEN}{self.config['software']}{Colors.RESET}")
        
        if self.config['software'] in ['papermc', 'spigot', 'purpur']:
            print(f"\n  1. Plugin Management")
            print(f"  2. Install from Modrinth (datapacks)")
        elif self.config['software'] in ['fabricmc', 'neoforge']:
            print(f"\n  1. Mod Management")
            print(f"  2. Install from Modrinth")
        else:
            print(f"\n  {Colors.YELLOW}Mods/Plugins not supported for {self.config['software']}{Colors.RESET}")
        
        print(f"  3. Back to Main Menu")
        
        choice = input(f"\n{Colors.CYAN}Select option: {Colors.RESET}")
        
        if choice == "1":
            self.manage_mods_plugins()
        elif choice == "2":
            self.install_from_modrinth()
    
    def manage_mods_plugins(self):
        os.system('clear')
        
        if self.config['software'] in ['papermc', 'spigot', 'purpur']:
            folder_name = "plugins"
        else:
            folder_name = "mods"
        
        folder_path = self.server_dir / folder_name
        folder_path.mkdir(exist_ok=True)
        
        self.print_colored(f"=== {folder_name.capitalize()} Management ===", Colors.CYAN)
        
        files = list(folder_path.glob("*.jar"))
        if not files:
            print(f"\n{Colors.YELLOW}No {folder_name} installed{Colors.RESET}")
        else:
            for i, file in enumerate(files, 1):
                size_mb = file.stat().st_size / (1024 * 1024)
                print(f"  {i}. {file.name} ({size_mb:.1f} MB)")
        
        print(f"\n  A. Add {folder_name[:-1]}")
        print(f"  D. Remove {folder_name[:-1]}")
        print(f"  B. Back")
        
        choice = input(f"\n{Colors.CYAN}Select: {Colors.RESET}").upper()
        
        if choice == "A":
            path = input(f"{Colors.GREEN}Enter path to .jar file: {Colors.RESET}")
            if os.path.exists(path) and path.endswith('.jar'):
                shutil.copy(path, folder_path)
                self.print_colored(f"{folder_name[:-1].capitalize()} added!", Colors.GREEN)
        
        elif choice == "D":
            if files:
                num = input(f"{Colors.RED}Enter number to remove: {Colors.RESET}")
                if num.isdigit() and 1 <= int(num) <= len(files):
                    files[int(num) - 1].unlink()
                    self.print_colored("Removed successfully", Colors.GREEN)
    
    def install_from_modrinth(self):
        os.system('clear')
        self.print_colored("=== Install from Modrinth ===", Colors.CYAN)
        
        print(f"\n{Colors.WHITE}Search for mods/plugins:{Colors.RESET}")
        query = input(f"{Colors.GREEN}Enter search term: {Colors.RESET}")
        
        if query:
            try:
                url = f"https://api.modrinth.com/v2/search?query={query}&limit=5"
                response = requests.get(url)
                data = response.json()
                
                hits = data.get('hits', [])
                if not hits:
                    print("No results found")
                else:
                    for i, hit in enumerate(hits, 1):
                        print(f"\n  {i}. {Colors.BOLD}{hit['title']}{Colors.RESET}")
                        print(f"     {hit['description'][:100]}")
                        print(f"     Downloads: {hit['downloads']}")
                    
                    choice = input(f"\n{Colors.GREEN}Select mod to install (or 0 to cancel): {Colors.RESET}")
                    if choice.isdigit() and 1 <= int(choice) <= len(hits):
                        selected = hits[int(choice) - 1]
                        self.download_modrinth_mod(selected)
            
            except Exception as e:
                print(f"Error: {e}")
        
        input("Press Enter to continue...")
    
    def download_modrinth_mod(self, mod_data):
        project_id = mod_data['project_id']
        versions_url = f"https://api.modrinth.com/v2/project/{project_id}/version"
        response = requests.get(versions_url)
        versions = response.json()
        
        if versions:
            latest = versions[0]
            files = latest['files']
            if files:
                download_url = files[0]['url']
                filename = files[0]['filename']
                
                if self.config['software'] in ['papermc', 'spigot', 'purpur']:
                    folder = self.server_dir / "plugins"
                else:
                    folder = self.server_dir / "mods"
                
                folder.mkdir(exist_ok=True)
                
                print(f"Downloading {filename}...")
                mod_response = requests.get(download_url)
                with open(folder / filename, 'wb') as f:
                    f.write(mod_response.content)
                self.print_colored(f"Installed: {filename}", Colors.GREEN)
    
    def performance_settings(self):
        os.system('clear')
        self.print_colored("=== Performance Settings ===", Colors.CYAN)
        
        print(f"\n{Colors.WHITE}Current RAM Allocation:{Colors.RESET} {Colors.GREEN}{self.config['allocated_ram']}{Colors.RESET}")
        print(f"\n{Colors.BOLD}RAM Options:{Colors.RESET}")
        
        ram_options = {
            "1": "512M",
            "2": "1G",
            "3": "2G",
            "4": "3G",
            "5": "4G",
            "6": "6G",
            "7": "8G"
        }
        
        for key, value in ram_options.items():
            marker = " [CURRENT]" if self.config['allocated_ram'] == value else ""
            print(f"  {key}. {value}{Colors.GREEN}{marker}{Colors.RESET}")
        
        print(f"  8. Custom")
        print(f"  9. View Distance: {self.config['view_distance']}")
        print(f"  10. Simulation Distance: {self.config['simulation_distance']}")
        print(f"  11. Max Players: {self.config['max_players']}")
        print(f"  12. Back")
        
        choice = input(f"\n{Colors.CYAN}Select: {Colors.RESET}")
        
        if choice in ram_options:
            self.config['allocated_ram'] = ram_options[choice]
        elif choice == "8":
            custom = input(f"{Colors.GREEN}Enter RAM (e.g., 1G, 512M): {Colors.RESET}")
            if custom:
                self.config['allocated_ram'] = custom
        elif choice == "9":
            vd = input(f"{Colors.GREEN}Enter view distance (3-32): {Colors.RESET}")
            if vd.isdigit():
                self.config['view_distance'] = int(vd)
        elif choice == "10":
            sd = input(f"{Colors.GREEN}Enter simulation distance (3-32): {Colors.RESET}")
            if sd.isdigit():
                self.config['simulation_distance'] = int(sd)
        elif choice == "11":
            mp = input(f"{Colors.GREEN}Enter max players: {Colors.RESET}")
            if mp.isdigit():
                self.config['max_players'] = int(mp)
        elif choice == "12":
            return
        
        self.save_config()
        self.apply_server_properties()
        self.performance_settings()
    
    def network_settings(self):
        os.system('clear')
        self.print_colored("=== Network & Security ===", Colors.CYAN)
        
        print(f"\n  1. Block Cracked Players: {Colors.GREEN if self.config['block_cracked'] else Colors.RED}{self.config['block_cracked']}{Colors.RESET}")
        print(f"  2. Whitelist: {Colors.GREEN if self.config['whitelist_enabled'] else Colors.RED}{self.config['whitelist_enabled']}{Colors.RESET}")
        print(f"  3. Server Port: {self.config['port']}")
        print(f"  4. Manage Whitelist")
        print(f"  5. Manage Banned Players")
        print(f"  6. Manage Banned IPs")
        print(f"  7. Manage OPs")
        print(f"  8. Back to Main Menu")
        
        choice = input(f"\n{Colors.CYAN}Select: {Colors.RESET}")
        
        if choice == "1":
            self.config['block_cracked'] = not self.config['block_cracked']
        elif choice == "2":
            self.config['whitelist_enabled'] = not self.config['whitelist_enabled']
        elif choice == "3":
            port = input(f"{Colors.GREEN}Enter port (default 25565): {Colors.RESET}")
            if port.isdigit():
                self.config['port'] = int(port)
        elif choice == "4":
            self.manage_whitelist()
        elif choice == "5":
            self.manage_banned_players()
        elif choice == "6":
            self.manage_banned_ips()
        elif choice == "7":
            self.manage_ops()
        elif choice == "8":
            return
        
        self.save_config()
        self.apply_server_properties()
        self.network_settings()
    
    def manage_whitelist(self):
        os.system('clear')
        self.print_colored("=== Whitelist Management ===", Colors.CYAN)
        
        whitelist = []
        if self.whitelist_file.exists():
            with open(self.whitelist_file, 'r') as f:
                whitelist = json.load(f)
        
        print(f"\n{Colors.WHITE}Whitelisted Players:{Colors.RESET}")
        for i, player in enumerate(whitelist, 1):
            print(f"  {i}. {player.get('name', 'Unknown')}")
        
        print(f"\n  A. Add Player")
        print(f"  D. Remove Player")
        print(f"  B. Back")
        
        choice = input(f"\n{Colors.CYAN}Select: {Colors.RESET}").upper()
        
        if choice == "A":
            name = input(f"{Colors.GREEN}Enter player name: {Colors.RESET}")
            if name:
                whitelist.append({"name": name, "uuid": "00000000-0000-0000-0000-000000000000"})
                with open(self.whitelist_file, 'w') as f:
                    json.dump(whitelist, f, indent=2)
                self.print_colored(f"Added {name} to whitelist", Colors.GREEN)
        
        elif choice == "D":
            if whitelist:
                num = input(f"{Colors.RED}Enter number to remove: {Colors.RESET}")
                if num.isdigit() and 1 <= int(num) <= len(whitelist):
                    removed = whitelist.pop(int(num) - 1)
                    with open(self.whitelist_file, 'w') as f:
                        json.dump(whitelist, f, indent=2)
                    self.print_colored(f"Removed {removed.get('name')}", Colors.GREEN)
    
    def manage_banned_players(self):
        os.system('clear')
        self.print_colored("=== Banned Players ===", Colors.CYAN)
        
        banned = []
        banned_file = self.server_dir / "banned-players.json"
        if banned_file.exists():
            with open(banned_file, 'r') as f:
                banned = json.load(f)
        
        print(f"\n{Colors.WHITE}Banned Players:{Colors.RESET}")
        for i, player in enumerate(banned, 1):
            print(f"  {i}. {player.get('name', 'Unknown')} - {player.get('reason', 'No reason')}")
        
        print(f"\n  A. Ban Player")
        print(f"  D. Unban Player")
        print(f"  B. Back")
        
        choice = input(f"\n{Colors.CYAN}Select: {Colors.RESET}").upper()
        
        if choice == "A":
            name = input(f"{Colors.GREEN}Enter player name: {Colors.RESET}")
            reason = input(f"{Colors.GREEN}Enter reason: {Colors.RESET}")
            if name:
                banned.append({
                    "name": name,
                    "uuid": "00000000-0000-0000-0000-000000000000",
                    "reason": reason or "Banned by admin",
                    "created": datetime.now().isoformat(),
                    "source": "Server Panel"
                })
                with open(banned_file, 'w') as f:
                    json.dump(banned, f, indent=2)
        
        elif choice == "D":
            if banned:
                num = input(f"{Colors.RED}Enter number to unban: {Colors.RESET}")
                if num.isdigit() and 1 <= int(num) <= len(banned):
                    banned.pop(int(num) - 1)
                    with open(banned_file, 'w') as f:
                        json.dump(banned, f, indent=2)
    
    def manage_banned_ips(self):
        os.system('clear')
        self.print_colored("=== Banned IPs ===", Colors.CYAN)
        
        banned_ips = []
        if self.banned_ips_file.exists():
            with open(self.banned_ips_file, 'r') as f:
                banned_ips = json.load(f)
        
        print(f"\n{Colors.WHITE}Banned IPs:{Colors.RESET}")
        for i, ip_entry in enumerate(banned_ips, 1):
            print(f"  {i}. {ip_entry.get('ip', 'Unknown')}")
        
        print(f"\n  A. Ban IP")
        print(f"  D. Unban IP")
        print(f"  B. Back")
        
        choice = input(f"\n{Colors.CYAN}Select: {Colors.RESET}").upper()
        
        if choice == "A":
            ip = input(f"{Colors.GREEN}Enter IP address: {Colors.RESET}")
            if ip:
                banned_ips.append({
                    "ip": ip,
                    "created": datetime.now().isoformat(),
                    "source": "Server Panel"
                })
                with open(self.banned_ips_file, 'w') as f:
                    json.dump(banned_ips, f, indent=2)
        
        elif choice == "D":
            if banned_ips:
                num = input(f"{Colors.RED}Enter number to unban: {Colors.RESET}")
                if num.isdigit() and 1 <= int(num) <= len(banned_ips):
                    banned_ips.pop(int(num) - 1)
                    with open(self.banned_ips_file, 'w') as f:
                        json.dump(banned_ips, f, indent=2)
    
    def manage_ops(self):
        os.system('clear')
        self.print_colored("=== Server Operators ===", Colors.CYAN)
        
        ops = []
        if self.ops_file.exists():
            with open(self.ops_file, 'r') as f:
                ops = json.load(f)
        
        print(f"\n{Colors.WHITE}Operators:{Colors.RESET}")
        for i, op in enumerate(ops, 1):
            level = op.get('level', 4)
            bypass = op.get('bypassesPlayerLimit', False)
            print(f"  {i}. {op.get('name', 'Unknown')} (Level: {level}, Bypass: {bypass})")
        
        print(f"\n  A. Add OP")
        print(f"  D. Remove OP")
        print(f"  B. Back")
        
        choice = input(f"\n{Colors.CYAN}Select: {Colors.RESET}").upper()
        
        if choice == "A":
            name = input(f"{Colors.GREEN}Enter player name: {Colors.RESET}")
            level = input(f"{Colors.GREEN}Enter OP level (1-4, default 4): {Colors.RESET}")
            if name:
                ops.append({
                    "name": name,
                    "uuid": "00000000-0000-0000-0000-000000000000",
                    "level": int(level) if level.isdigit() else 4,
                    "bypassesPlayerLimit": False
                })
                with open(self.ops_file, 'w') as f:
                    json.dump(ops, f, indent=2)
        
        elif choice == "D":
            if ops:
                num = input(f"{Colors.RED}Enter number to remove: {Colors.RESET}")
                if num.isdigit() and 1 <= int(num) <= len(ops):
                    ops.pop(int(num) - 1)
                    with open(self.ops_file, 'w') as f:
                        json.dump(ops, f, indent=2)
    
    def player_management(self):
        os.system('clear')
        self.print_colored("=== Player Management ===", Colors.CYAN)
        
        print(f"\n  1. View Online Players")
        print(f"  2. Kick Player")
        print(f"  3. Ban Player")
        print(f"  4. Whitelist Player")
        print(f"  5. OP Player")
        print(f"  6. Back to Main Menu")
        
        choice = input(f"\n{Colors.CYAN}Select: {Colors.RESET}")
        
        if choice == "1":
            print(f"\n{Colors.YELLOW}Connect to server console to view online players{Colors.RESET}")
        elif choice == "2":
            player = input(f"{Colors.GREEN}Enter player name to kick: {Colors.RESET}")
            print(f"Kicked {player} (requires server running)")
        elif choice == "3":
            self.manage_banned_players()
        elif choice == "4":
            self.manage_whitelist()
        elif choice == "5":
            self.manage_ops()
    
    def apply_server_properties(self):
        properties = {
            "motd": self.config['server_description'],
            "gamemode": self.config['gamemode'],
            "difficulty": self.config['difficulty'],
            "hardcore": str(self.config['hardcore']).lower(),
            "pvp": str(self.config['pvp']).lower(),
            "allow-flight": str(self.config['allow_flight']).lower(),
            "enable-command-block": str(self.config['enable_command_block']).lower(),
            "max-players": str(self.config['max_players']),
            "view-distance": str(self.config['view_distance']),
            "simulation-distance": str(self.config['simulation_distance']),
            "online-mode": str(not self.config['block_cracked']).lower(),
            "white-list": str(self.config['whitelist_enabled']).lower(),
            "server-port": str(self.config['port']),
            "level-type": self.config['world_type'],
            "spawn-protection": str(self.config['spawn_protection']),
            "allow-nether": str(self.config['allow_nether']).lower()
        }
        
        if self.server_properties.exists():
            with open(self.server_properties, 'r') as f:
                lines = f.readlines()
            
            new_lines = []
            updated_keys = set()
            
            for line in lines:
                if '=' in line:
                    key = line.split('=')[0].strip()
                    if key in properties:
                        new_lines.append(f"{key}={properties[key]}\n")
                        updated_keys.add(key)
                    else:
                        new_lines.append(line)
                else:
                    new_lines.append(line)
            
            for key, value in properties.items():
                if key not in updated_keys:
                    new_lines.append(f"{key}={value}\n")
            
            with open(self.server_properties, 'w') as f:
                f.writelines(new_lines)
        else:
            with open(self.server_properties, 'w') as f:
                f.write("# Minecraft Server Properties\n")
                for key, value in properties.items():
                    f.write(f"{key}={value}\n")
    
    def start_server(self):
        self.save_config()
        self.apply_server_properties()
        
        if self.config.get("auto_update"):
            self.check_and_auto_update()
        
        os.chdir(self.server_dir)
        
        memory = self.config['allocated_ram']
        initial_memory = "512M"
        
        java_args = [
            "java",
            f"-Xmx{memory}",
            f"-Xms{initial_memory}",
            "-jar", "server.jar",
            "nogui"
        ]
        
        self.print_colored("Starting server...", Colors.GREEN)
        print(f"Command: {' '.join(java_args)}")
        
        try:
            subprocess.run(java_args)
        except KeyboardInterrupt:
            self.print_colored("\nServer stopped", Colors.YELLOW)
        except Exception as e:
            self.print_colored(f"Error: {e}", Colors.RED)


def main():
    server_dir = Path.home() / "minecraft-server"
    if not server_dir.exists():
        print("Server directory not found. Run installer first.")
        return
    
    panel = ServerPanel(server_dir)
    panel.main_menu()


if __name__ == "__main__":
    main()
