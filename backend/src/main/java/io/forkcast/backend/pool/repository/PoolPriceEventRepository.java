package io.forkcast.backend.pool.repository;

import io.forkcast.backend.pool.domain.PoolPriceEvent;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PoolPriceEventRepository extends JpaRepository<PoolPriceEvent, Long> {
  boolean existsByTxHashAndLogIndex(String txHash, int logIndex);

  List<PoolPriceEvent> findByPoolIdOrderByEventTimestampDesc(String poolId, Pageable pageable);

}
