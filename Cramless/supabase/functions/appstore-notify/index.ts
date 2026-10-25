// The `appstore-notify` Edge Function: App Store Server Notifications V2. Set its URL in App Store Connect
// (App Information → App Store Server Notifications, Version 2) for Production and Sandbox.

import { defaultDeps } from "../_shared/deps.ts";
import { logFault } from "../_shared/log.ts";
import { appstoreNotifyHandler } from "./handler.ts";

const deps = defaultDeps();
for (const fault of deps.env.faults) logFault("appstore-notify", fault);
Deno.serve(appstoreNotifyHandler(deps));
