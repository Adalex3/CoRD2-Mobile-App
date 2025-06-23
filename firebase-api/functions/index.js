const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

// Load the secret key from functions config
const SECRET_KEY = functions.config().api.key;

// HTTP function: returns latest doc from 'events' collection
exports.getLatestData = functions.https.onRequest(async (req, res) => {
  const apiKey = req.get("x-api-key");
  if (!apiKey || apiKey !== SECRET_KEY) {
    return res.status(403).json({ error: "Unauthorized" });
  }
  try {
    const snapshot = await admin
      .firestore()
      .collection("events")
      .orderBy("timestamp", "desc")
      .limit(1)
      .get();
    const data = snapshot.docs.map((doc) => doc.data());
    res.json(data);
  } catch (err) {
    console.error("Error fetching data:", err);
    res.status(500).json({ error: "Internal Server Error" });
  }
});