package io.forkcast.backend.position.repository;

import io.forkcast.backend.position.domain.StrategyPosition;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface StrategyPositionRepository extends JpaRepository<StrategyPosition, Long> {
  List<StrategyPosition> findByIsOpenTrue();

  List<StrategyPosition> findByOwnerAddressAndIsOpenTrueOrderByOpenedBlockDesc(String ownerAddress, Pageable pageable);
  List<StrategyPosition> findByIsOpenTrueOrderByOpenedBlockDesc(Pageable pageable);


}
