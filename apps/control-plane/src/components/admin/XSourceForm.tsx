"use client";

import { useState } from "react";

function normalizedXHandle(value: string) {
  return value.trim().replace(/^@+/, "");
}

export function nextXDisplayName(input: {
  requestedHandle: string;
  currentDisplayName: string;
  displayNameEdited: boolean;
}) {
  if (input.displayNameEdited) return input.currentDisplayName;
  const handle = normalizedXHandle(input.requestedHandle);
  return handle ? `@${handle}` : "";
}

export function xCreationPayload(displayName: string, requestedHandle: string) {
  return {
    display_name: displayName.trim(),
    requested_handle: normalizedXHandle(requestedHandle),
  };
}

export function XSourceForm() {
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [requestedHandle, setRequestedHandle] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [displayNameEdited, setDisplayNameEdited] = useState(false);

  async function submit() {
    setPending(true);
    setMessage(null);
    try {
      const response = await fetch("/api/admin/x/sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(xCreationPayload(displayName, requestedHandle)),
      });
      if (!response.ok) {
        setMessage("未能创建博主。请检查 X 账号、展示名称和管理员权限后重试。");
        return;
      }
      setMessage("X 博主已创建。下一步：完成身份验证并初始化覆盖范围。");
      window.location.reload();
    } finally {
      setPending(false);
    }
  }

  return (
    <form action={submit} className="source-create-form">
      <h2>新建 X 博主</h2>
      <p className="source-creation-intro">填写要跟踪的账号；系统会完成内部关联，并在身份验证后开始采集。</p>
      <label>
        X 账号
        <span className="source-handle-field">
          <span aria-hidden="true">@</span>
          <input
            name="requested_handle"
            required
            maxLength={128}
            value={requestedHandle}
            onChange={(event) => {
              const nextHandle = event.target.value;
              setRequestedHandle(nextHandle);
              setDisplayName((currentName) => nextXDisplayName({
                requestedHandle: nextHandle,
                currentDisplayName: currentName,
                displayNameEdited,
              }));
            }}
            placeholder="例如：researcher"
            aria-describedby="x-handle-note"
          />
        </span>
        <small id="x-handle-note">无需输入 @；账号会用于身份验证。</small>
      </label>
      <label>
        展示名称
        <input
          name="display_name"
          required
          maxLength={128}
          value={displayName}
          onChange={(event) => {
            setDisplayNameEdited(true);
            setDisplayName(event.target.value);
          }}
          placeholder="例如：研究博主 A"
        />
      </label>
      <p className="source-creation-preset" role="note">
        <strong>采集方案</strong>
        <span>标准采集（推荐）</span>
        <small>系统自动维护</small>
      </p>
      <button type="submit" disabled={pending}>{pending ? "创建中…" : "创建 X 博主"}</button>
      {message ? <p role="status">{message}</p> : null}
    </form>
  );
}
