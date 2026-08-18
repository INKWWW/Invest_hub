"use client";

import { FormEvent, useState } from "react";

import { isValidRegistrationPassword } from "../../../lib/auth/password";

const genericRegistrationError = "无法完成注册。请检查邀请码和注册信息；如果已经注册，请直接登录。";

export default function InvitePage() {
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const code = form.get("code");
    const email = form.get("email");
    const password = form.get("password");
    const passwordConfirmation = form.get("password_confirmation");
    const inviteCode = typeof code === "string" ? code.trim() : "";
    const address = typeof email === "string" ? email.trim() : "";
    const secret = typeof password === "string" ? password : "";
    const confirmation = typeof passwordConfirmation === "string" ? passwordConfirmation : "";

    if (!inviteCode || !address || !secret || !confirmation) {
      setError("请填写邀请码、邮箱、密码和确认密码。");
      return;
    }
    if (!isValidRegistrationPassword(secret)) {
      setError("密码至少 8 位，且包含大写字母、小写字母和数字。");
      return;
    }
    if (secret !== confirmation) {
      setError("两次输入的密码不一致。");
      return;
    }

    let response: Response;
    try {
      response = await fetch("/api/auth/invite", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          code: inviteCode,
          email: address,
          password: secret,
          password_confirmation: confirmation,
        }),
      });
    } catch {
      setError(genericRegistrationError);
      return;
    }
    if (!response.ok) {
      setError(genericRegistrationError);
      return;
    }
    window.location.assign("/agent");
  }

  return (
    <main className="auth-page">
      <section className="auth-card">
        <p className="reader-kicker">Invest Hub</p>
        <h1>创建受邀账号</h1>
        <form onSubmit={submit}>
          <label>
            注册邀请码
            <input name="code" required />
          </label>
          <label>
            邮箱
            <input name="email" type="email" autoComplete="email" required />
          </label>
          <label>
            密码 <small>至少 8 位，且包含大写字母、小写字母和数字</small>
            <input name="password" type="password" autoComplete="new-password" required />
          </label>
          <label>
            确认密码
            <input name="password_confirmation" type="password" autoComplete="new-password" required />
          </label>
          <button type="submit">创建账号</button>
        </form>
        <p className="auth-secondary-action"><a href="/login">返回登录</a></p>
        {error ? <p role="alert">{error}</p> : null}
      </section>
    </main>
  );
}
