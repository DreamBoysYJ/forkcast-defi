package io.forkcast.backend.chain.repository;

import io.forkcast.backend.chain.domain.RawChainEvent;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface RawChainEventRepository extends JpaRepository<RawChainEvent, Long> {


  Optional<RawChainEvent> findByTxHashAndLogIndex(String txHash, int logIndex);

  boolean existsByTxHashAndLogIndex(String txHash, int logIndex);

  List<RawChainEvent> findTop100ByBlockNumberBetweenOrderByBlockNumberAscLogIndexAsc(
    long startBlock, long endBlock
  );

  List<RawChainEvent> findTop100ByEventNameOrderByBlockNumberDescLogIndexDesc(String eventName);



};
