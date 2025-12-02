// index.js
const { S3Client, ListObjectsV2Command } = require("@aws-sdk/client-s3");
const s3 = new S3Client({});

exports.handler = async () => {
  console.log("Lambda triggered");
  const res = await s3.send(new ListObjectsV2Command({
    Bucket: process.env.BUCKET_NAME
  }));
  console.log("Objects:", res.Contents || []);
  return { statusCode: 200, body: JSON.stringify(res.Contents || []) };
};
