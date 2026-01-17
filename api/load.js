export default async function handler(req, res) {
  const m = req.query.m
  if (!m) return res.status(400).send("no module")

  const r = await fetch(
    "https://raw.githubusercontent.com/xexxnx18-prog/QuickTools/main/" +
      m + ".lua",
    {
      headers: {
        Authorization: "token " + process.env.GH_TOKEN
      }
    }
  )

  if (!r.ok) return res.status(404).send("not found")
  res.setHeader("Content-Type", "text/plain")
  res.send(await r.text())
}
