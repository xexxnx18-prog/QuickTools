import requests

print("\n[DOWNLOAD]")
print("Starting PaperMC download...\n")

response = requests.get(downloadUrl, stream=True)

totalSize = int(response.headers.get("content-length", 0))
downloaded = 0

with open("server.jar", "wb") as file:

    for chunk in response.iter_content(chunk_size=8192):

        if not chunk:
            continue

        file.write(chunk)

        downloaded += len(chunk)

        if totalSize:
            percent = int(downloaded * 100 / totalSize)
            print(f"\r[{percent}%] Downloading...", end="")

print("\n[✓] Download complete")
print("[✓] Saved as server.jar")
