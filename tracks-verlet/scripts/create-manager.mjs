// Creates (or resets) a manager account with an email + password.
// Usage: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/create-manager.mjs boss@verlet.co 'password' 'Full Name'
import { createClient } from "@supabase/supabase-js";

const [email, password, fullName] = process.argv.slice(2);
if (!email || !password) {
  console.error("Usage: node scripts/create-manager.mjs <email> <password> [full name]");
  process.exit(1);
}
const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}
const admin = createClient(url, key, { auth: { persistSession: false } });

const { data: list } = await admin.auth.admin.listUsers({ perPage: 1000 });
const existing = list?.users.find((u) => u.email?.toLowerCase() === email.toLowerCase());
if (existing) {
  const { error } = await admin.auth.admin.updateUserById(existing.id, { password, app_metadata: { role: "manager" } });
  if (error) throw error;
  await admin.from("profiles").update({ role: "manager", ...(fullName ? { full_name: fullName } : {}) }).eq("id", existing.id);
  console.log(`Updated ${email}: password reset, role manager`);
} else {
  const { error } = await admin.auth.admin.createUser({
    email, password, email_confirm: true,
    app_metadata: { role: "manager" }, user_metadata: { full_name: fullName ?? null },
  });
  if (error) throw error;
  console.log(`Created manager ${email}`);
}
