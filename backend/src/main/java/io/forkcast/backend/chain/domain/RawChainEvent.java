package io.forkcast.backend.chain.domain;


import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.ColumnTransformer;

import java.time.Instant;

@Entity
@Table(name = "raw_chain_event")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class RawChainEvent {


  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "event_name", nullable = false, length = 100)
  private String eventName;

  @Column(name = "tx_hash", nullable = false, length = 66)
  private String txHash;

  @Column(name = "block_number", nullable = false, length = 66)
  private long blockNumber;

  @Column(name = "block_hash", nullable = false, length = 66)
  private String blockHash;

  @Column(name = "log_index", nullable = false)
  private int logIndex;

  @Column(name = "contract_address", nullable = false, length = 42)
  private String contractAddress;

  @Column(name = "payload_json", nullable = false, columnDefinition = "jsonb")
  @ColumnTransformer(write = "?::jsonb")
  private String payloadJson;

  @Column(name = "event_timestamp", nullable = false)
  private Instant eventTimestamp;

  @Column(name = "removed", nullable = false)
  private boolean removed;

  public RawChainEvent(
    String eventName,
    String txHash,
    long blockNumber,
    String blockHash,
    int logIndex,
    String contractAddress,
    String payloadJson,
    Instant eventTimestamp,
    boolean removed
  ) {
    this.eventName = eventName;
    this.txHash = txHash;
    this.blockNumber = blockNumber;
    this.blockHash = blockHash;
    this.logIndex = logIndex;
    this.contractAddress = contractAddress;
    this.payloadJson = payloadJson;
    this.eventTimestamp = eventTimestamp;
    this.removed = removed;
  }
}
