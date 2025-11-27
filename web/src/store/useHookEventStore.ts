// src/store/useHookEventStore.ts
"use client";

import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";

export type UiHookEvent = {
  id: string;
  source: "DEMO_TRADER" | "USER_TX";
  txHash: `0x${string}`;
  poolId: `0x${string}`;
  tick: number;
  sqrtPriceX96: string;
  timestampMs: number;
};

type HookEventState = {
  events: UiHookEvent[];
  addMany: (evts: UiHookEvent[]) => void;
  addOne: (evt: UiHookEvent) => void;
  clear: () => void;
};

export const useHookEventStore = create<HookEventState>()(
  persist(
    (set, get) => ({
      events: [],
      addMany: (evts) =>
        set(() => ({
          events: [...get().events, ...evts],
        })),
      addOne: (evt) =>
        set(() => ({
          events: [...get().events, evt],
        })),
      clear: () => set({ events: [] }),
    }),
    {
      name: "hook-event-store", // 🔑 localStorage key
      storage: createJSONStorage(() => localStorage),
    }
  )
);
