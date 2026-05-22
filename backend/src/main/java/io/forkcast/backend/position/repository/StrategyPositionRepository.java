package io.forkcast.backend.position.repository;

import io.forkcast.backend.position.domain.StrategyPosition;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface StrategyPositionRepository extends JpaRepository<StrategyPosition, Long> {
  List<StrategyPosition> findByIsOpenTrue();

  List<StrategyPosition> findByOwnerAddressAndIsOpenTrueOrderByOpenedBlockDesc(String ownerAddress, Pageable pageable);
  List<StrategyPosition> findByIsOpenTrueOrderByOpenedBlockDesc(Pageable pageable);

  @Modifying
  @Query(value = """
      INSERT INTO strategy_position
          (token_id, owner_address, vault_address, supply_asset, borrow_asset,
           is_open, opened_block, closed_block, opened_tx_hash, closed_tx_hash)
      VALUES
          (:tokenId, :ownerAddress, :vaultAddress, :supplyAsset, :borrowAsset,
           :isOpen, :openedBlock, :closedBlock, :openedTxHash, :closedTxHash)
      ON CONFLICT (token_id) DO NOTHING
      """, nativeQuery = true)
  int insertIfAbsent(
      @Param("tokenId") Long tokenId,
      @Param("ownerAddress") String ownerAddress,
      @Param("vaultAddress") String vaultAddress,
      @Param("supplyAsset") String supplyAsset,
      @Param("borrowAsset") String borrowAsset,
      @Param("isOpen") boolean isOpen,
      @Param("openedBlock") long openedBlock,
      @Param("closedBlock") Long closedBlock,
      @Param("openedTxHash") String openedTxHash,
      @Param("closedTxHash") String closedTxHash
  );
}
