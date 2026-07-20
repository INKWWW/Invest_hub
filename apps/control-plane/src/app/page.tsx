import { getCurrentUser } from "../lib/auth/current-user";
import { redirect } from "next/navigation";

export default async function HomePage() {
  const user = await getCurrentUser();
  if (!user) return <main><h1>Invest Hub</h1><p>Please sign in.</p></main>;
  redirect(user.role === "admin" ? "/admin" : "/discord");
}
