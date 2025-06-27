const express = require("express");
const cors = require("cors");
const admin = require("firebase-admin");
const functions = require("firebase-functions");
admin.initializeApp();

const app = express();
app.use(cors());
app.use(express.json());

// Auth middleware: verify Firebase ID token
app.use(async (req, res, next) => {
  const auth = req.header("Authorization") || "";
  const match = auth.match(/^Bearer (.+)$/);
  if (!match) return res.status(401).json({ error: "Missing ID token" });

  try {
    const idToken = match[1];
    req.user = await admin.auth().verifyIdToken(idToken);
    return next();
  } catch (e) {
    console.error("Auth error:", e);
    return res.status(403).json({ error: "Invalid or expired ID token" });
  }
});

// GET /events?limit=x
app.get("/events", async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit,10) || 10, 100);
  try {
    const snapshot = await admin
      .firestore()
      .collection("events")
      .orderBy("time", "desc")
      .limit(limit)
      .get();
    res.json(snapshot.docs.map(d => ({ id: d.id, ...d.data() })));
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "Internal Server Error" });
  }
});

// GET /events/:id
app.get("/events/:id", async (req, res) => {
  try {
    const doc = await admin
      .firestore()
      .collection("events")
      .doc(req.params.id)
      .get();
    if (!doc.exists) return res.status(404).json({ error: "Not Found" });
    res.json({ id: doc.id, ...doc.data() });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "Internal Server Error" });
  }
});

exports.api = functions.https.onRequest(app);