/// REPLACED in v2 by the network-agnostic account sheet:
/// `lib/screens/networks/network_account_sheet.dart`.
///
/// Every network — WhatsApp included — now shares one disconnect path
/// through `AccountLifecycleService` (bridge logout → instant room wipe →
/// sticky cache flag), so per-network sheets can never drift apart again.
/// Kept only because the deployment sandbox forbids deleting files.
library removed_whatsapp_disconnect;
