package io.forkcast.backend.position.dto;

import io.forkcast.backend.position.domain.StrategyPosition;

public record OpenPositionResponse(
  Long tokenId,
  String ownerAddress,
  String vaultAddress,
  String supplyAsset,
  String borrowAsset,
  boolean isOpen,
  long openedBlock,
  String openedTxHash
) {
  public static OpenPositionResponse from(StrategyPosition position) {
    return new OpenPositionResponse(
      position.getTokenId(),
      position.getOwnerAddress(),
      position.getVaultAddress(),
      position.getSupplyAsset(),
      position.getBorrowAsset(),
      position.isOpen(),
      position.getOpenedBlock(),
      position.getOpenedTxHash()
    );
  }
}
