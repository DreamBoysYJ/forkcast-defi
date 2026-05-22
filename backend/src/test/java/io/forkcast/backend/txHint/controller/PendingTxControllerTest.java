package io.forkcast.backend.txHint.controller;

import io.forkcast.backend.txHint.domain.PendingTx;
import io.forkcast.backend.txHint.service.PendingTxService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(properties = {
    "sync.rpc.url=http://localhost:8545",
    "sync.contracts.strategy-router-address=0x0000000000000000000000000000000000000000",
    "sync.contracts.hook-address=0x0000000000000000000000000000000000000000",
    "STRATEGY_LENS_ADDRESS=0x0000000000000000000000000000000000000000"
})
class PendingTxControllerTest {

    @Autowired
    private WebApplicationContext context;

    @MockitoBean
    private PendingTxService pendingTxService;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).build();
    }

    @Test
    void 정상_요청시_202_반환() throws Exception {
        // given
        String txHash = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        PendingTx pendingTx = new PendingTx(txHash, "OPEN_POSITION", "0x7a227d5902ca52c0c3c61304533bff4632fce145");
        when(pendingTxService.create(any(), any(), any())).thenReturn(pendingTx);

        String body = "{\"txHash\":\"" + txHash + "\","
            + "\"actionType\":\"OPEN_POSITION\","
            + "\"userAddress\":\"0x7a227d5902ca52c0c3c61304533bff4632fce145\"}";

        // when & then
        mockMvc.perform(post("/api/tx-hints")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
            .andExpect(status().isAccepted())
            .andExpect(jsonPath("$.status").value("ACCEPTED"))
            .andExpect(jsonPath("$.txHash").value(txHash));
    }

    @Test
    void 중복_txHash_요청시_409_반환() throws Exception {
        // given
        String txHash = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        when(pendingTxService.create(any(), any(), any()))
            .thenThrow(new DataIntegrityViolationException("duplicate"));

        String body = "{\"txHash\":\"" + txHash + "\","
            + "\"actionType\":\"OPEN_POSITION\","
            + "\"userAddress\":\"0x7a227d5902ca52c0c3c61304533bff4632fce145\"}";

        // when & then
        mockMvc.perform(post("/api/tx-hints")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("DUPLICATE_TX_HASH"));
    }

    @Test
    void 필수_필드_누락시_400_반환() throws Exception {
        // given — txHash 없음
        String body = "{\"actionType\":\"OPEN_POSITION\",\"userAddress\":\"0x7a227d5902ca52c0c3c61304533bff4632fce145\"}";

        // when & then
        mockMvc.perform(post("/api/tx-hints")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
            .andExpect(status().isBadRequest());
    }
}
