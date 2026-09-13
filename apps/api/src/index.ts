import { Elysia } from "elysia";
import { MongoClient, ObjectId, type OptionalUnlessRequiredId, type UpdateFilter } from "mongodb";

interface Item {
  _id?: ObjectId;
  revision: number;
  [key: string]: unknown;
}

const mongoClient = new MongoClient(
  process.env.DATABASE_URL ?? "mongodb://mongo:27017/mydatabase?directConnection=true&retryWrites=true&w=majority&replicaSet=rs0"
);
await mongoClient.connect();
const db = mongoClient.db("mydatabase");
const items = db.collection<Item>("items");

const app = new Elysia();
app.get("/", () => "Hello Elysia");

app.post("/save", async ({ body }) => {
  const doc = { ...(body as object), revision: 1 } as OptionalUnlessRequiredId<Item>;
  const result = await items.insertOne(doc);
  return { insertedId: result.insertedId };
});

app.patch("/items/:id", async ({ params, body, set }) => {
  const { revision, _id, ...changes } = body as Record<string, unknown>;
  const result = await items.findOneAndUpdate(
    { _id: new ObjectId(params.id) },
    { $set: changes, $inc: { revision: 1 } } as unknown as UpdateFilter<Item>,
    { returnDocument: "after" }
  );

  if (!result) {
    set.status = 404;
    return { error: "Item not found" };
  }

  return result;
});

app.listen(process.env.PORT ?? 3000);

console.log(
  `🦊 Elysia is running at ${app.server?.hostname}:${app.server?.port}`
);
