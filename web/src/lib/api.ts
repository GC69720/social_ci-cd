const base = process.env.NEXT_PUBLIC_API_BASE || "http://localhost:8000";
export async function health(): Promise<{ status: string }> {
  const res = await fetch(`${base}/health`);
  if (!res.ok) throw new Error("Healthcheck failed");
  return res.json();
}
