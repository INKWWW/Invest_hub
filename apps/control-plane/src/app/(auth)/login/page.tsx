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
      setError("邮箱或密码不正确，请重试。");
      return;
    }
    window.location.assign("/");
  }

  return (
    <main className="auth-page">
      <section className="auth-card">
        <p className="reader-kicker">Invest Hub</p>
        <h1>登录 Invest Hub</h1>
        <form onSubmit={submit}>
          <label>
            邮箱
            <input name="email" type="email" autoComplete="email" required />
          </label>
          <label>
            密码
            <input name="password" type="password" autoComplete="current-password" required />
          </label>
          <button type="submit">登录</button>
        </form>
        <p className="auth-secondary-action"><a href="/invite">有邀请码？创建账号</a></p>
        {error ? <p role="alert">{error}</p> : null}
      </section>
    </main>
  );
}
