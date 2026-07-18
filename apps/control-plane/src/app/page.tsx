import { getCurrentUser } from "../lib/auth/current-user";

export default async function HomePage() {
  const user = await getCurrentUser();
  if (!user) return <main><h1>Invest Hub V0</h1><p>Please sign in.</p></main>;
  return (
    <main>
      <h1>Invest Hub V0</h1>
      <p>Signed in as {user.email ?? user.id}.</p>
      <p>Role: {user.role}. Task status is available to authorized administrators.</p>
    </main>
  );
}
