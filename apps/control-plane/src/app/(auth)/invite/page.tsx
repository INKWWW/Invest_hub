"use client";

import { FormEvent, useState } from "react";

export default function InvitePage() {
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const response = await fetch("/api/auth/invite", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: form.get("code"), email: form.get("email"), password: form.get("password") }),
    });
    if (!response.ok) {
      setError((await response.json()).error ?? "Unable to redeem invite.");
      return;
    }
    window.location.assign("/login");
  }

  return (
    <main>
      <h1>Redeem invite</h1>
      <form onSubmit={submit}>
        <label>
          Invite code
          <input name="code" required />
        </label>
        <label>
          Email
          <input name="email" type="email" autoComplete="email" required />
        </label>
        <label>
          Password
          <input name="password" type="password" autoComplete="new-password" required />
        </label>
        <button type="submit">Create account</button>
      </form>
      {error ? <p role="alert">{error}</p> : null}
    </main>
  );
}
