import shutil
import subprocess

def java():

    print("\n[JAVA]")
    print("Checking Java installation...")

    if shutil.which("java"):
        print("[✓] Java found")
        return True

    print("[!] Java not found")
    print("Installing OpenJDK 21...")

    subprocess.run([
        "pkg",
        "install",
        "-y",
        "openjdk-21"
    ])

    print("[✓] Java ready")

    return True
