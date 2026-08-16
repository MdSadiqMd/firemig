#!/usr/bin/env node
import { FiremigClient } from "@firemig/sdk";
import { runDemo } from "./demo.js";

const client = new FiremigClient({
    baseUrl: process.env.FIREMIG_API_URL ?? "http://127.0.0.1:4000",
    userId: process.env.FIREMIG_USER_ID ?? "demo-user",
    ...(process.env.FIREMIG_API_TOKEN === undefined
        ? {}
        : { token: process.env.FIREMIG_API_TOKEN }),
});
const report = await runDemo({
    client,
    source: process.env.FIREMIG_SOURCE ?? "worker-a",
    destination: process.env.FIREMIG_DESTINATION ?? "worker-b",
});
process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
if (!report.passed) process.exitCode = 1;
