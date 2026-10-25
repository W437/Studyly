// The `account` Edge Function. Dependencies are built once per instance.

import { defaultDeps } from "../_shared/deps.ts";
import { logFault } from "../_shared/log.ts";
import { accountHandler } from "./handler.ts";

const deps = defaultDeps();
for (const fault of deps.env.faults) logFault("account", fault);
Deno.serve(accountHandler(deps));
