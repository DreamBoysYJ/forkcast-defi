package io.forkcast.backend.snapshot.client;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.web3j.abi.FunctionEncoder;
import org.web3j.abi.FunctionReturnDecoder;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.Function;
import org.web3j.abi.datatypes.Type;
import org.web3j.abi.datatypes.generated.Int24;
import org.web3j.abi.datatypes.generated.Uint128;
import org.web3j.abi.datatypes.generated.Uint160;
import org.web3j.abi.datatypes.generated.Uint256;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.core.DefaultBlockParameterNumber;
import org.web3j.protocol.core.methods.request.Transaction;

import java.io.IOException;
import java.math.BigDecimal;
import java.math.BigInteger;
import java.util.List;

@Component
public class StrategyLensClient {
  private static final BigInteger MAX_UINT256 = BigInteger.ONE.shiftLeft(256).subtract(BigInteger.ONE);
  private static final BigDecimal MAX_STORABLE_HEALTH_FACTOR =
    new BigDecimal("99999999999999999999.999999999999999999");

  private final Web3j web3j;
  private final String strategyLensAddress;

  public StrategyLensClient(
    Web3j web3j,
    @Value("${STRATEGY_LENS_ADDRESS}") String strategyLensAddress
  ) {
    this.web3j = web3j;
    this.strategyLensAddress = strategyLensAddress;
  }

  public PositionState getPositionState(String ownerAddress, Long tokenId, long observedBlockNumber) {
    List<Type> aaveOverview = call(
      new Function(
        "getUserAaveOverview",
        List.of(new Address(ownerAddress)),
        List.of(
          new TypeReference<Address>() {},
          new TypeReference<Address>() {},
          new TypeReference<Uint256>() {},
          new TypeReference<Uint256>() {},
          new TypeReference<Uint256>() {},
          new TypeReference<Uint256>() {},
          new TypeReference<Uint256>() {},
          new TypeReference<Uint256>() {}
        )
      ),
      observedBlockNumber
    );

    List<Type> uniPosition = call(
      new Function(
        "getUserUniPosition",
        List.of(
          new Address(ownerAddress),
          new Uint256(BigInteger.valueOf(tokenId))
        ),
        List.of(
          new TypeReference<Address>() {},
          new TypeReference<Address>() {},
          new TypeReference<Uint128>() {},
          new TypeReference<Uint256>() {},
          new TypeReference<Uint256>() {},
          new TypeReference<Int24>() {},
          new TypeReference<Int24>() {},
          new TypeReference<Int24>() {},
          new TypeReference<Uint160>() {}
        )
      ),
      observedBlockNumber
    );

    BigInteger liquidity = (BigInteger) uniPosition.get(2).getValue();
    BigInteger amount0Now = (BigInteger) uniPosition.get(3).getValue();
    BigInteger amount1Now = (BigInteger) uniPosition.get(4).getValue();
    Integer currentTick = ((BigInteger) uniPosition.get(7).getValue()).intValue();
    BigInteger sqrtPriceX96 = (BigInteger) uniPosition.get(8).getValue();

    BigInteger totalCollateralBase = (BigInteger) aaveOverview.get(2).getValue();
    BigInteger totalDebtBase = (BigInteger) aaveOverview.get(3).getValue();
    BigDecimal healthFactor = normalizeHealthFactor(
      (BigInteger) aaveOverview.get(7).getValue(),
      totalDebtBase
    );

    return new PositionState(
      liquidity,
      amount0Now,
      amount1Now,
      currentTick,
      sqrtPriceX96,
      totalCollateralBase,
      totalDebtBase,
      healthFactor
    );
  }

  private List<Type> call(Function function, long observedBlockNumber) {
    String encodedFunction = FunctionEncoder.encode(function);

    try {
      String value = web3j.ethCall(
          Transaction.createEthCallTransaction(null, strategyLensAddress, encodedFunction),
          new DefaultBlockParameterNumber(observedBlockNumber)
        )
        .send()
        .getValue();

      return FunctionReturnDecoder.decode(value, function.getOutputParameters());
    } catch (IOException e) {
      throw new IllegalStateException("failed to call StrategyLens", e);
    }
  }

  private BigDecimal toWadDecimal(BigInteger raw) {
    return new BigDecimal(raw).movePointLeft(18);
  }

  private BigDecimal normalizeHealthFactor(BigInteger raw, BigInteger totalDebtBase) {
    // Aave may return uint256 max when debt is 0, which is effectively "infinite".
    // Persist the largest storable finite value instead of failing the whole snapshot job.
    if (totalDebtBase.signum() == 0 || raw.equals(MAX_UINT256)) {
      return MAX_STORABLE_HEALTH_FACTOR;
    }

    BigDecimal decimal = toWadDecimal(raw);
    if (decimal.compareTo(MAX_STORABLE_HEALTH_FACTOR) > 0) {
      return MAX_STORABLE_HEALTH_FACTOR;
    }

    return decimal;
  }

  public record PositionState(
    BigInteger liquidity,
    BigInteger amount0Now,
    BigInteger amount1Now,
    Integer currentTick,
    BigInteger sqrtPriceX96,
    BigInteger totalCollateralBase,
    BigInteger totalDebtBase,
    BigDecimal healthFactor
  ) {
  }
}
