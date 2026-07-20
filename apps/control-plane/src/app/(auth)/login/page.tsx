"use client";

import { FormEvent, useState } from "react";

export default function LoginPage() {
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const response = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: form.get("email"), password: form.get("password") }),
    });
    if (!response.ok) {
      setError((await response.json()).error ?? "Unable to sign in.");
      return;
    }
    window.location.assign("/");
  }

  return (
    <main className="auth-page">
      <section className="auth-card">
        <p className="reader-kicker">Invest Hub</p>
        <h1>Sign in to your research workspace</h1>
        <form onSubmit={submit}>
          <label>
            Email
            <input name="email" type="email" autoComplete="email" required />
          </label>
          <label>
            Password
            <input name="password" type="password" autoComplete="current-password" required />
          </label>
          <button type="submit">Sign in</button>
        </form>
        {error ? <p role="alert">{error}</p> : null}
      </section>
    </main>
  );
}
