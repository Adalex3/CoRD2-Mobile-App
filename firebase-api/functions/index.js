const express = require("express");
const cors = require("cors");
const admin = require("firebase-admin");
admin.initializeApp();

const SECRET_KEY = "01b912290d4522301de4582bfe8b331b1cd7825a315341c562c578f87dcfc6ce";

const app = express();
app.use(cors());             // allow cross-origin requests
app.use(express.json());     // parse JSON bodies

// Auth middleware
app.use((req, res, next) => {
  const key = req.get("x-api-key");
  if (!key || key !== SECRET_KEY) {
    return res.status(403).json({ error: "Unauthorized" });
  }
  next();
});

// GET /events?limit=x
app.get("/events", async (req, res) => {
  const limit = parseInt(req.query.limit, 10) || 10;
  try {
    const snapshot = await admin
      .firestore()
      .collection("events")
      .orderBy("time", "desc")
      .limit(limit)
      .get();
    const data = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    res.json(data);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Internal Server Error" });
  }
});

// GET /events/:id
app.get("/events/:id", async (req, res) => {
  try {
    const doc = await admin.firestore().collection("events").doc(req.params.id).get();
    if (!doc.exists) {
      return res.status(404).json({ error: "Not Found" });
    }
    res.json({ id: doc.id, ...doc.data() });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Internal Server Error" });
  }
});

// Export as a single Firebase Function
exports.api = require("firebase-functions").https.onRequest(app);