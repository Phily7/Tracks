export default function Setup() {
  return (
    <main className="mx-auto max-w-xl px-4 py-16">
      <h1 className="font-display text-3xl tracking-tight">Tracks Verlet needs a database</h1>
      <p className="mt-3 text-muted">
        Set <code>NEXT_PUBLIC_SUPABASE_URL</code> and <code>NEXT_PUBLIC_SUPABASE_ANON_KEY</code>, run{" "}
        <code>supabase/migrations/0001_init.sql</code>, then reload. See <code>README.md</code>.
      </p>
    </main>
  );
}
