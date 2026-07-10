import { execSync } from "child_process";
import { TEST_DATABASE_URL, assertTestDatabase } from "./test-db-url";

export default function globalSetup() {
  assertTestDatabase(TEST_DATABASE_URL);
  execSync("./node_modules/.bin/prisma migrate deploy", {
    stdio: "inherit",
    env: { ...process.env, DATABASE_URL: TEST_DATABASE_URL },
  });
}
