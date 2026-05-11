import type { QueryClient } from "@tanstack/react-query";

export async function refreshActiveQueries(queryClient: QueryClient) {
  await queryClient.invalidateQueries({
    refetchType: "active",
  });
}
