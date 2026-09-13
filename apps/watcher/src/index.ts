import {
  MongoClient,
  type ChangeStreamDocument,
  type Collection,
  type Db,
  type Document,
  type ResumeToken,
} from "mongodb";

interface WatcherState {
  _id: string;
  resumeToken?: ResumeToken;
  updatedAt?: Date;
}

const DATABASE_URL =
  process.env.DATABASE_URL ??
  "mongodb://mongo:27017/mydatabase?directConnection=true&retryWrites=true&w=majority&replicaSet=rs0";
const DB_NAME = "mydatabase";
const HEALTH_PORT = Number(process.env.HEALTH_PORT ?? 3002);
const INITIAL_BACKOFF_MS = 1_000;
const MAX_BACKOFF_MS = 30_000;
const RESUME_STATE_COLLECTION = "_watcher_state";
const RESUME_STATE_ID = "change_stream";
const CHANGE_STREAM_HISTORY_LOST = 286;

const client = new MongoClient(DATABASE_URL);

let ready = false;
let shuttingDown = false;
let shutdownResolve: (() => void) | undefined;
const shutdownSignal = new Promise<void>((resolve) => {
  shutdownResolve = resolve;
});

function sleep(ms: number) {
  return Promise.race([
    new Promise((resolve) => setTimeout(resolve, ms)),
    shutdownSignal,
  ]);
}

async function getResumeToken(
  stateCollection: Collection<WatcherState>
): Promise<ResumeToken | undefined> {
  const state = await stateCollection.findOne({ _id: RESUME_STATE_ID });
  return state?.resumeToken;
}

async function watchWithRetry(db: Db) {
  const stateCollection = db.collection<WatcherState>(RESUME_STATE_COLLECTION);
  let backoff = INITIAL_BACKOFF_MS;

  while (!shuttingDown) {
    const resumeToken = await getResumeToken(stateCollection);
    const changeStream = db.watch(
      [{ $match: { "ns.coll": { $ne: RESUME_STATE_COLLECTION } } }],
      {
        fullDocument: "updateLookup",
        ...(resumeToken ? { resumeAfter: resumeToken } : {}),
      }
    );

    try {
      await new Promise<void>((resolve, reject) => {
        changeStream.on("change", (change: ChangeStreamDocument<Document>) => {
          console.log(JSON.stringify(change));
          backoff = INITIAL_BACKOFF_MS;
          ready = true;
          stateCollection
            .updateOne(
              { _id: RESUME_STATE_ID },
              { $set: { resumeToken: change._id, updatedAt: new Date() } },
              { upsert: true }
            )
            .catch((err) => console.error("Failed to persist resume token:", err));
        });
        changeStream.once("error", reject);
        changeStream.once("close", () => resolve());
      });
    } catch (err: any) {
      console.error("Change stream error:", err);
      if (err?.code === CHANGE_STREAM_HISTORY_LOST) {
        console.warn("Resume token invalid (history lost), resuming from now");
        await stateCollection.deleteOne({ _id: RESUME_STATE_ID });
      }
    } finally {
      ready = false;
      await changeStream.close().catch(() => {});
    }

    if (shuttingDown) break;

    console.log(`Reconnecting change stream in ${backoff}ms...`);
    await sleep(backoff);
    backoff = Math.min(backoff * 2, MAX_BACKOFF_MS);
  }
}

const healthServer = Bun.serve({
  port: HEALTH_PORT,
  fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/health") {
      return new Response("ok");
    }
    if (url.pathname === "/ready") {
      return ready
        ? new Response("ok")
        : new Response("not ready", { status: 503 });
    }
    return new Response("not found", { status: 404 });
  },
});

async function main() {
  await client.connect();
  const db = client.db(DB_NAME);
  console.log(`Watching changes on database "${db.databaseName}"`);
  await watchWithRetry(db);
}

async function shutdown() {
  console.log("Shutting down watcher...");
  shuttingDown = true;
  shutdownResolve?.();
  healthServer.stop();
  await client.close();
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

main().catch((err) => {
  console.error("Failed to start watcher:", err);
  process.exit(1);
});
