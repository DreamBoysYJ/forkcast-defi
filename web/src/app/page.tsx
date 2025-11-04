import Connect from "@/components/Connect";

export default function Page() {
  return (
    <main className="p-6">
      <h1 className="text-xl font-semibold">Forkcast Demo</h1>
      <p className="text-sm text-gray-500">
        Aave ↔ Uniswap v4 one-shot + demo volume
      </p>
      <div className="mt-6 flex gap-3">
        <Connect />
        <button className="border rounded px-3 py-2">Open (one-shot)</button>
        <button className="border rounded px-3 py-2">Demo Volume</button>
      </div>
    </main>
  );
}
