"use client";

import { Suspense, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase/client";
import { Logo } from "@/components/Logo";

export default function LoginPage() {
  return (
    <Suspense>
      <Login />
    </Suspense>
  );
}

function Login() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get("next") || "/";
  const [mode, setMode] = useState<"engineer" | "manager">("engineer");
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [password, setPassword] = useState("");
  const [codeSent, setCodeSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(params.get("error") === "link" ? "That sign-in link expired or was already used. Ask for a new one." : "");

  async function sendCode(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const sb = supabase();
    const { data: allowed, error: rpcError } = await sb.rpc("can_sign_in", { addr: email });
    if (rpcError || !allowed) {
      setBusy(false);
      setError(rpcError ? rpcError.message : "This email isn't set up for Tracks Verlet. Ask your manager to add you.");
      return;
    }
    // Implicit flow for the email link, so it opens in any browser (see /auth/callback).
    const linkClient = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
      auth: { flowType: "implicit", persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const { error } = await linkClient.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: true, emailRedirectTo: `${location.origin}/auth/callback` },
    });
    setBusy(false);
    if (error) setError(error.message);
    else setCodeSent(true);
  }

  async function verifyCode(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const { error } = await supabase().auth.verifyOtp({ email, token: code.trim(), type: "email" });
    setBusy(false);
    if (error) setError(error.message);
    else router.replace(next);
  }

  async function passwordLogin(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const { error } = await supabase().auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) setError(error.message);
    else router.replace(next);
  }

  return (
    <main className="min-h-screen flex items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 flex flex-col items-center gap-3 text-center">
          <Logo size={40} />
          <div>
            <h1 className="font-display text-3xl tracking-tight">Tracks Verlet</h1>
            <p className="hint mt-1">Turn your BOM into a procurement request that&apos;s ready to send.</p>
          </div>
        </div>

        <div className="card p-5">
          <div className="mb-5 grid grid-cols-2 gap-1 rounded-lg bg-bg p-1 text-sm" role="tablist">
            {(["engineer", "manager"] as const).map((m) => (
              <button
                key={m}
                role="tab"
                aria-selected={mode === m}
                onClick={() => { setMode(m); setError(""); setCodeSent(false); }}
                className={`h-8 rounded-md font-medium capitalize ${mode === m ? "bg-panel shadow-sm" : "text-muted"}`}
              >
                {m}
              </button>
            ))}
          </div>

          {mode === "engineer" && !codeSent && (
            <form onSubmit={sendCode} className="space-y-4">
              <div>
                <label className="label" htmlFor="email">Work email</label>
                <input id="email" className="input" type="email" required autoFocus value={email}
                  onChange={(e) => setEmail(e.target.value)} placeholder="you@verlet.co" />
              </div>
              <button className="btn btn-primary w-full" disabled={busy}>{busy ? "Sending…" : "Email me a sign-in code"}</button>
              <p className="hint text-center">No password. We email you a sign-in link.</p>
            </form>
          )}

          {mode === "engineer" && codeSent && (
            <form onSubmit={verifyCode} className="space-y-4">
              <p className="text-sm">We emailed <strong>{email}</strong>. Click the link in it (any browser or phone is fine), or type the code if the email shows one.</p>
              <div>
                <label className="label" htmlFor="code">Code</label>
                <input id="code" className="input text-center font-mono text-lg tracking-[0.3em]" inputMode="numeric"
                  autoComplete="one-time-code" required autoFocus maxLength={8} value={code}
                  onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} />
              </div>
              <button className="btn btn-primary w-full" disabled={busy || code.length < 6}>{busy ? "Checking…" : "Sign in"}</button>
              <button type="button" className="btn btn-ghost w-full" onClick={() => { setCodeSent(false); setCode(""); }}>
                Use a different email
              </button>
            </form>
          )}

          {mode === "manager" && (
            <form onSubmit={passwordLogin} className="space-y-4">
              <div>
                <label className="label" htmlFor="m-email">Email</label>
                <input id="m-email" className="input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
              </div>
              <div>
                <label className="label" htmlFor="m-pass">Password</label>
                <input id="m-pass" className="input" type="password" required value={password} onChange={(e) => setPassword(e.target.value)} />
              </div>
              <button className="btn btn-primary w-full" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
              <p className="hint text-center">
                No password?{" "}
                <button type="button" className="text-accent-text hover:underline" onClick={() => { setMode("engineer"); setError(""); }}>
                  Sign in with an email link
                </button>{" "}
                — managers can too.
              </p>
            </form>
          )}

          {error && <p className="mt-4 rounded-md bg-bad-soft px-3 py-2 text-sm text-bad" role="alert">{error}</p>}
        </div>
      </div>
    </main>
  );
}
