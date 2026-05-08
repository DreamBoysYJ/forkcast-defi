package io.forkcast.backend.snapshot.domain;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.time.Instant;

@Entity
@Table(
  name = "position_snapshot",
  uniqueConstraints = {
    @UniqueConstraint(
      name = "uq_position_snapshot_token_id_snapshot_at",
      columnNames = {"token_id", "snapshot_at"}
    )
  }
)
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class PositionSnapshot {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

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

  @Column(name = "liquidity", precision = 78, scale = 0)
  private BigInteger liquidity;

  @Column(name = "amount0_now", precision = 78, scale = 0)
  private BigInteger amount0Now;

  @Column(name = "amount1_now", precision = 78, scale = 0)
  private BigInteger amount1Now;

  @Column(name = "current_tick")
  private Integer currentTick;

  @Column(name = "sqrt_price_x96", precision = 78, scale = 0)
  private BigInteger sqrtPriceX96;

  @Column(name = "total_collateral_base", precision = 78, scale = 0)
  private BigInteger totalCollateralBase;

  @Column(name = "total_debt_base", precision = 78, scale = 0)
  private BigInteger totalDebtBase;

  @Column(name = "health_factor", precision = 38, scale = 18)
  private BigDecimal healthFactor;

  @Column(name = "snapshot_at", nullable = false)
  private Instant snapshotAt;

  @Column(name = "observed_block_number", nullable = false)
  private long observedBlockNumber;

  public boolean isOpen() {
    return isOpen;
  }

  public PositionSnapshot(
    Long tokenId,
    String ownerAddress,
    String vaultAddress,
    String supplyAsset,
    String borrowAsset,
    boolean isOpen,
    BigInteger liquidity,
    BigInteger amount0Now,
    BigInteger amount1Now,
    Integer currentTick,
    BigInteger sqrtPriceX96,
    BigInteger totalCollateralBase,
    BigInteger totalDebtBase,
    BigDecimal healthFactor,
    Instant snapshotAt,
    long observedBlockNumber
  ) {
    this.tokenId = tokenId;
    this.ownerAddress = ownerAddress;
    this.vaultAddress = vaultAddress;
    this.supplyAsset = supplyAsset;
    this.borrowAsset = borrowAsset;
    this.isOpen = isOpen;
    this.liquidity = liquidity;
    this.amount0Now = amount0Now;
    this.amount1Now = amount1Now;
    this.currentTick = currentTick;
    this.sqrtPriceX96 = sqrtPriceX96;
    this.totalCollateralBase = totalCollateralBase;
    this.totalDebtBase = totalDebtBase;
    this.healthFactor = healthFactor;
    this.snapshotAt = snapshotAt;
    this.observedBlockNumber = observedBlockNumber;
  }
}
