// index.js
const { S3Client, CopyObjectCommand } = require("@aws-sdk/client-s3");
const { Client } = require("pg");

const s3 = new S3Client({});

const sanitizeIdentifier = (identifier) => {
  if (!identifier || !/^[A-Za-z0-9_]+$/.test(identifier)) {
    throw new Error("Invalid table identifier supplied");
  }
  return identifier;
};

exports.s3Replicator = async (event) => {
  const sourceBucket = process.env.SOURCE_BUCKET;
  const destBucket = process.env.DEST_BUCKET;

  if (!sourceBucket || !destBucket) {
    throw new Error("Bucket environment variables are not set");
  }

  console.log("Received event:", JSON.stringify(event));
  const records = event?.Records ?? [];
  if (records.length === 0) {
    console.log("No records to process");
    return;
  }

  for (const record of records) {
    const key = decodeURIComponent(record?.s3?.object?.key ?? "");
    if (!key) {
      console.log("Skipping record with no key", record);
      continue;
    }

    console.log(`Copying ${key} to backup bucket`);
    const encodedSource = encodeURIComponent(key).replace(/%2F/g, "/");
    await s3.send(
      new CopyObjectCommand({
        Bucket: destBucket,
        CopySource: `${sourceBucket}/${encodedSource}`,
        Key: key
      })
    );
  }

  return { statusCode: 200, body: JSON.stringify({ copied: records.length }) };
};

exports.dbBackup = async () => {
  const tableName = sanitizeIdentifier(process.env.TABLE_NAME || "inventory_sample");
  const dbUser = process.env.DB_USER;
  const dbPassword = process.env.DB_PASSWORD;

  if (!dbUser || !dbPassword) {
    throw new Error("Database credentials are not set");
  }

  const sourceClient = new Client({
    host: process.env.SOURCE_DB_HOST,
    port: Number(process.env.SOURCE_DB_PORT || 5432),
    database: process.env.SOURCE_DB_NAME,
    user: dbUser,
    password: dbPassword
  });

  const targetClient = new Client({
    host: process.env.TARGET_DB_HOST,
    port: Number(process.env.TARGET_DB_PORT || 5432),
    database: process.env.TARGET_DB_NAME,
    user: dbUser,
    password: dbPassword
  });

  const tableDDL = `
    CREATE TABLE IF NOT EXISTS ${tableName} (
      item_id INTEGER PRIMARY KEY,
      item_name TEXT NOT NULL,
      quantity INTEGER NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `;

  await sourceClient.connect();
  await targetClient.connect();

  try {
    await Promise.all([sourceClient.query(tableDDL), targetClient.query(tableDDL)]);
    const { rows } = await sourceClient.query(
      `SELECT item_id, item_name, quantity, updated_at FROM ${tableName} ORDER BY item_id`
    );
    console.log(`Fetched ${rows.length} rows from source ${tableName}`);

    await targetClient.query(`TRUNCATE TABLE ${tableName}`);

    for (const row of rows) {
      await targetClient.query(
        `INSERT INTO ${tableName} (item_id, item_name, quantity, updated_at)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (item_id) DO UPDATE
         SET item_name = EXCLUDED.item_name,
             quantity = EXCLUDED.quantity,
             updated_at = EXCLUDED.updated_at`,
        [row.item_id, row.item_name, row.quantity, row.updated_at]
      );
    }
    console.log(`Replicated ${rows.length} rows into backup database`);
  } finally {
    await sourceClient.end();
    await targetClient.end();
  }

  return { statusCode: 200, body: JSON.stringify({ copiedRows: "complete" }) };
};
