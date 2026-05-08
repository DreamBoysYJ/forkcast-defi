package io.forkcast.backend.pool.domain;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.math.BigInteger;
import java.time.Instant;

@Entity
@Table(
  name = "pool_price_event",
  uniqueConstraints = {
    @UniqueConstraint(
      name = "uq_pool_price_event_tx_hash_log_index",
      columnNames = {"tx_hash", "log_index"}
    )
  }
)
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class PoolPriceEvent {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "pool_id", nullable = false)
  private String poolId;

  @Column(name = "tx_hash", nullable = false, length = 66)
  private String txHash;

  @Column(name = "block_number", nullable = false)
  private long blockNumber;

  @Column(name = "log_index", nullable = false)
  private int logIndex;

  @Column(name = "tick", nullable = false)
  private int tick;

  @Column(name = "sqrt_price_x96", nullable = false, precision = 78, scale = 0)
  private BigInteger sqrtPriceX96;

  @Column(name = "event_timestamp", nullable = false)
  private Instant eventTimestamp;

  public PoolPriceEvent(
    String poolId,
    String txHash,
    long blockNumber,
    int logIndex,
    int tick,
    BigInteger sqrtPriceX96,
    Instant eventTimestamp
  ) {
    this.poolId = poolId;
    this.txHash = txHash;
    this.blockNumber = blockNumber;
    this.logIndex = logIndex;
    this.tick = tick;
    this.sqrtPriceX96 = sqrtPriceX96;
    this.eventTimestamp = eventTimestamp;
  }
}
