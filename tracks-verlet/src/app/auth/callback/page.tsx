"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase/client";

// Sign-in link landing page. The link is sent with the implicit flow, so Supabase redirects here with the
// session in the URL fragment. That works in any browser or device, unlike PKCE links, which only work in
// the browser that asked for them.
export default function AuthCallback() {
  const router = useRouter();
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const hash = new URLSearchParams(window.location.hash.slice(1));
    const access_token = hash.get("access_token");
    const refresh_token = hash.get("refresh_token");
    if (!access_token || !refresh_token) {
      router.replace("/login?error=link");
      return;
    }
    supabase().auth.setSession({ access_token, refresh_token }).then((res: { error: unknown }) => {
      if (res.error) setFailed(true);
      else router.replace("/");
    });
  }, [router]);

  return (
    <main className="flex min-h-screen items-center justify-center px-4 text-sm text-muted">
      {failed ? "That sign-in link didn't work. Go back and ask for a new one." : "Signing you in…"}
    </main>
  );
}
