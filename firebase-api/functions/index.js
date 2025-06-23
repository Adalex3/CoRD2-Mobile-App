const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const SECRET_KEY = "01b912290d4522301de4582bfe8b331b1cd7825a315341c562c578f87dcfc6ce";

// v1 HTTPS function on Node 18
exports.getLatestData = functions.https.onRequest(async (req, res) => {
  const apiKey = req.get("x-api-key");
  if (!apiKey || apiKey !== SECRET_KEY) {
    return res.status(403).json({ error: "Unauthorized" });
  }
  try {
    const snapshot = await admin
        .firestore()
        .collection("events")
        .orderBy("time", "desc")
        .limit(1)
        .get();
    const data = snapshot.docs.map((doc) => doc.data());
    res.json(data);
  } catch (err) {
    console.error("Error fetching data:", err);
    res.status(500).json({ error: "Internal Server Error" });
  }
});