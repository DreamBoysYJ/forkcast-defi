import Providers from "@/components/Providers";
import "./globals.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Forkcast DeFi",
  description: "Preview & run a one-shot Aave → Uniswap v4 LP strategy.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
