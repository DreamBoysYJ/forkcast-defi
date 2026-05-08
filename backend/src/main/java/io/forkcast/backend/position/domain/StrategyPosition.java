package io.forkcast.backend.position.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "strategy_position")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class StrategyPosition {

  @Id
  @Column(name = "token_id", nullable = false)
  private Long tokenId;

  @Column(name = "owner_address", nullable = false, length = 42)
  private String ownerAddress;

  @Column(name = "vault_address", nullable = false, length = 42)
  private String vaultAddress;

  @Column(name = "supply_asset", nullable = false, length = 42)
  private String supplyAsset;

  @Column(name = "borrow_asset", nullable = false, length = 42)
  private String borrowAsset;

  @Column(name = "is_open", nullable = false)
  private boolean isOpen;

  @Column(name = "opened_block", nullable = false)
  private long openedBlock;

  @Column(name = "closed_block")
  private Long closedBlock;

  @Column(name = "opened_tx_hash", nullable = false, length = 66)
  private String openedTxHash;

  @Column(name = "closed_tx_hash", length = 66)
  private String closedTxHash;

  public StrategyPosition(
    Long tokenId,
    String ownerAddress,
    String vaultAddress,
    String supplyAsset,
    String borrowAsset,
    boolean isOpen,
    long openedBlock,
    Long closedBlock,
    String openedTxHash,
    String closedTxHash
  ) {
    this.tokenId = tokenId;
    this.ownerAddress = ownerAddress;
    this.vaultAddress = vaultAddress;
    this.supplyAsset = supplyAsset;
    this.borrowAsset = borrowAsset;
    this.isOpen = isOpen;
    this.openedBlock = openedBlock;
    this.closedBlock = closedBlock;
    this.openedTxHash = openedTxHash;
    this.closedTxHash = closedTxHash;
  }

  public void close(long closedBlock, String closedTxHash) {
    this.isOpen = false;
    this.closedBlock = closedBlock;
    this.closedTxHash = closedTxHash;
  }
}
