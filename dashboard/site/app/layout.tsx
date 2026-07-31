import type { Metadata, Viewport } from "next";
import "./globals.css";


export const metadata: Metadata = {
  title: "Product Growth Analytics | Decision Dashboard",
  description:
    "An aggregate-only ecommerce product analytics dashboard covering the ordered funnel, segment diagnosis, checkout telemetry, and A/B test design.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
  openGraph: {
    title: "Product Growth Analytics",
    description:
      "Test a simpler checkout. Do not claim the cause yet.",
    type: "website",
    images: [
      {
        url: "/product-growth-social.png",
        width: 1200,
        height: 630,
        alt: "Abstract product funnel and experiment analytics illustration",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Product Growth Analytics",
    description:
      "A decision dashboard for funnel diagnosis and checkout experimentation.",
    images: ["/product-growth-social.png"],
  },
};

export const viewport: Viewport = {
  themeColor: "#101b29",
  colorScheme: "light",
};


export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
