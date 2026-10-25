// The `ai` Edge Function. Dependencies are built once per instance; configuration faults are logged at every
// cold start.

import { defaultDeps } from "../_shared/deps.ts";
import { logFault } from "../_shared/log.ts";
import { aiHandler } from "./handler.ts";

const deps = defaultDeps();
for (const fault of deps.env.faults) logFault("ai", fault);
Deno.serve(aiHandler(deps));
