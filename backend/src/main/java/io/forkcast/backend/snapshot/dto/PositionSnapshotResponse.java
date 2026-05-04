package io.forkcast.backend.snapshot.dto;

import io.forkcast.backend.snapshot.domain.PositionSnapshot;

import java.time.Instant;

public record PositionSnapshotResponse(
  Long tokenId,
  String ownerAddress,
  String vaultAddress,
  String supplyAsset,
  String borrowAsset,
  boolean isOpen,
  String liquidity,
  String amount0Now,
  String amount1Now,
  Integer currentTick,
  String sqrtPriceX96,
  String totalCollateralBase,
  String totalDebtBase,
  String healthFactor,
  Instant snapshotAt,
  long observedBlockNumber
) {
  public static PositionSnapshotResponse from(PositionSnapshot snapshot) {
    return new PositionSnapshotResponse(
      snapshot.getTokenId(),
      snapshot.getOwnerAddress(),
      snapshot.getVaultAddress(),
      snapshot.getSupplyAsset(),
      snapshot.getBorrowAsset(),
      snapshot.isOpen(),
      snapshot.getLiquidity() == null ? null : snapshot.getLiquidity().toString(),
      snapshot.getAmount0Now() == null ? null : snapshot.getAmount0Now().toString(),
      snapshot.getAmount1Now() == null ? null : snapshot.getAmount1Now().toString(),
      snapshot.getCurrentTick(),
      snapshot.getSqrtPriceX96() == null ? null : snapshot.getSqrtPriceX96().toString(),
      snapshot.getTotalCollateralBase() == null ? null : snapshot.getTotalCollateralBase().toString(),
      snapshot.getTotalDebtBase() == null ? null : snapshot.getTotalDebtBase().toString(),
      snapshot.getHealthFactor() == null ? null : snapshot.getHealthFactor().toPlainString(),
      snapshot.getSnapshotAt(),
      snapshot.getObservedBlockNumber()
    );
  }
}
