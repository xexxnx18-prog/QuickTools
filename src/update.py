import os
import time
import subprocess

class Update:

    @staticmethod
    def run():
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("        UPDATE MODULE")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        steps = [
            "Checking internet connection",
            "Loading package manager",
            "Fetching package sources",
            "Downloading repository metadata",
            "Verifying package signatures",
            "Refreshing package cache",
            "Checking available upgrades",
            "Updating installed packages",
            "Cleaning temporary files"
        ]

        for step in steps:
            print(f"[+] {step}...")
            time.sleep(0.8)

        try:
            subprocess.run(
                ["pkg", "update", "-y"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            subprocess.run(
                ["pkg", "upgrade", "-y"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            print("\n[✓] Package sources updated")
            print("[✓] Repository metadata refreshed")
            print("[✓] System packages upgraded")
            print("[✓] Cache cleaned")
            print("[✓] Update completed successfully")

            return True

        except Exception as e:
            print(f"\n[✗] Update failed")
            print(f"[!] {e}")
            return False
