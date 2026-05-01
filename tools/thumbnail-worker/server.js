import express from "express";
import {Storage} from "@google-cloud/storage";

const app = express();
app.use(express.json({limit: "2mb"}));

const storage = new Storage();
const bucketName = process.env.THUMBNAIL_BUCKET || process.env.FIREBASE_STORAGE_BUCKET || "";

app.post("/", async (req, res) => {
  const {sessionId, jobId, boardId} = req.body || {};
  if (!sessionId || !jobId || !boardId) {
    res.status(400).json({error: "missing_fields"});
    return;
  }
  if (!bucketName) {
    res.status(500).json({error: "missing_bucket"});
    return;
  }

  const bucket = storage.bucket(bucketName);
  const objectPath = `sessions/${sessionId}/thumbnails/${boardId}.png`;
  const file = bucket.file(objectPath);

  // Placeholder PNG (1x1 transparent) to keep pipeline running.
  const pngBuffer = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6XW3xQAAAAASUVORK5CYII=",
    "base64",
  );

  await file.save(pngBuffer, {
    contentType: "image/png",
    resumable: false,
    metadata: {
      cacheControl: "public, max-age=3600",
    },
  });

  res.json({ok: true, storagePath: objectPath});
});

const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log(`thumbnail worker listening on ${port}`);
});
