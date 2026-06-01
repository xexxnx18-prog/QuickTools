import requests

print("\n[SOURCES]")
print("Getting PaperMC versions...\n")

try:
    versions = requests.get(
        "https://api.papermc.io/v2/projects/paper"
    ).json()["versions"]

    versions.reverse()

    for i, version in enumerate(versions, 1):
        print(f"[{i}] Minecraft {version}")

    versionChoice = int(input("\nSelect Minecraft version: "))
    version = versions[versionChoice - 1]

    print(f"\nGetting builds for {version}...\n")

    builds = requests.get(
        f"https://api.papermc.io/v2/projects/paper/versions/{version}"
    ).json()["builds"]

    builds.reverse()

    for i, build in enumerate(builds, 1):
        print(f"[{i}] Build {build}")

    buildChoice = int(input("\nSelect build: "))
    build = builds[buildChoice - 1]

    downloadUrl = (
        f"https://api.papermc.io/v2/projects/paper/"
        f"versions/{version}/builds/{build}/downloads/"
        f"paper-{version}-{build}.jar"
    )

    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"Minecraft Version : {version}")
    print(f"Paper Build       : {build}")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("\nDownload URL:")
    print(downloadUrl)

except Exception as e:
    print(f"\nFailed to get PaperMC sources: {e}")
