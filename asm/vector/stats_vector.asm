; =============================================================
; stats_vector.asm
; Version VECTORIZADA (AVX2, 8 floats por iteracion) de los
; kernels de computo. Misma ABI que la version escalar.
;
; Antes de compilar/ejecutar en su maquina, confirme soporte AVX2:
;   lscpu | grep avx2
;   cat /proc/cpuinfo | grep avx2
; =============================================================

    global sum_array
    global compute_stats
    global normalize_array

    section .text

; ---------------------------------------------------------------
; float sum_array(const float *arr, int n)
;   rdi = arr, esi = n -> retorna la suma en xmm0
; ---------------------------------------------------------------
sum_array:
    xor     eax, eax               ; eax = i = 0
    vxorps  ymm0, ymm0, ymm0       ; ymm0 = acumulador vectorial = 0

    mov     ecx, esi
    and     ecx, ~7                ; ecx = n redondeado hacia abajo, multiplo de 8
    test    ecx, ecx
    jle     .sum_reduce

.sum_vec_loop:
    cmp     eax, ecx
    jge     .sum_reduce
    vmovups ymm1, [rdi + rax*4]    ; carga 8 floats
    vaddps  ymm0, ymm0, ymm1       ; acumula por carril
    add     eax, 8
    jmp     .sum_vec_loop

.sum_reduce:
    ; --- reduccion horizontal: 8 carriles de ymm0 -> un escalar ---
    vextractf128 xmm2, ymm0, 1     ; xmm2 = mitad alta (carriles 4-7)
    vaddps  xmm0, xmm0, xmm2       ; xmm0 = 4 sumas parciales
    vhaddps xmm0, xmm0, xmm0       ; suma horizontal
    vhaddps xmm0, xmm0, xmm0       ; xmm0[0] = suma total

.sum_scalar_tail:
    ; --- elementos sobrantes (n % 8), uno a la vez ---
    cmp     eax, esi
    jge     .sum_done
    vmovss  xmm1, [rdi + rax*4]
    vaddss  xmm0, xmm0, xmm1
    inc     eax
    jmp     .sum_scalar_tail

.sum_done:
    vzeroupper
    ret


; ---------------------------------------------------------------
; void compute_stats(const float *arr, int n,
;                     float *mean, float *var, float *min, float *max)
;   rdi = arr, esi = n, rdx = mean*, rcx = var*, r8 = min*, r9 = max*
;
; Algoritmo:
;   1) Primera pasada VECTORIZADA: sum, min, max
;   2) mean = sum / n
;   3) Segunda pasada VECTORIZADA: sum_sq = Σ(x - mean)²
;   4) var = sum_sq / n
;   5) Guardar resultados en los punteros
;   6) Si n == 0, escribir 0.0 en los cuatro
;
; Registros:
;   rdi = arr, esi = n
;   r12 = mean*, r13 = var*, r14 = min*, r15 = max*
;   xmm0 = sum / sum_sq (acumulador escalar tras reduccion)
;   xmm1 = min (escalar tras reduccion)
;   xmm2 = max (escalar tras reduccion)
;   xmm6 = mean (escalar, PRESERVADO durante segunda pasada)
;   xmm4 = (float)n
;   ymm0/ymm3/ymm5 = acumuladores vectoriales
;   ymm7 = mean broadcast (segunda pasada)
; ---------------------------------------------------------------
compute_stats:
    ; --- Guardar registros callee-saved ---
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; --- Validar n > 0 ---
    test    esi, esi
    jz      .cs_error_n_zero

    ; --- Guardar punteros de salida en registros callee-saved ---
    mov     r12, rdx               ; r12 = mean*
    mov     r13, rcx               ; r13 = var*
    mov     r14, r8                ; r14 = min*
    mov     r15, r9                ; r15 = max*

    ; ============================================================
    ; PRIMERA PASADA VECTORIZADA: sum, min, max
    ; ============================================================
    vxorps  ymm0, ymm0, ymm0       ; ymm0 = sum (8 carriles) = 0

    ; Inicializar min/max con el primer elemento (broadcast)
    vbroadcastss ymm1, [rdi]       ; ymm1 = min = arr[0] (8 carriles)
    vbroadcastss ymm2, [rdi]       ; ymm2 = max = arr[0] (8 carriles)

    xor     eax, eax               ; eax = i = 0
    mov     ecx, esi
    and     ecx, ~7                ; ecx = n redondeado a multiplo de 8

    test    ecx, ecx
    jle     .cs_pass1_reduce

.cs_pass1_loop:
    cmp     eax, ecx
    jge     .cs_pass1_reduce
    vmovups ymm3, [rdi + rax*4]    ; ymm3 = arr[i..i+7]
    vaddps  ymm0, ymm0, ymm3       ; sum += arr[i..i+7]
    vminps  ymm1, ymm1, ymm3       ; min = min(min, arr)
    vmaxps  ymm2, ymm2, ymm3       ; max = max(max, arr)
    add     eax, 8
    jmp     .cs_pass1_loop

.cs_pass1_reduce:
    ; --- Reduccion horizontal de sum (ymm0 -> xmm0[0]) ---
    vextractf128 xmm3, ymm0, 1
    vaddps  xmm0, xmm0, xmm3
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0       ; xmm0[0] = suma total

    ; --- Reduccion horizontal de min (ymm1 -> xmm1[0]) ---
    vextractf128 xmm3, ymm1, 1
    vminps  xmm1, xmm1, xmm3
    vshufps xmm3, xmm1, xmm1, 0x0E
    vminps  xmm1, xmm1, xmm3
    vshufps xmm3, xmm1, xmm1, 0x01
    vminps  xmm1, xmm1, xmm3       ; xmm1[0] = min total

    ; --- Reduccion horizontal de max (ymm2 -> xmm2[0]) ---
    vextractf128 xmm3, ymm2, 1
    vmaxps  xmm2, xmm2, xmm3
    vshufps xmm3, xmm2, xmm2, 0x0E
    vmaxps  xmm2, xmm2, xmm3
    vshufps xmm3, xmm2, xmm2, 0x01
    vmaxps  xmm2, xmm2, xmm3       ; xmm2[0] = max total

    ; --- Bucle escalar de cierre para sum, min, max ---
.cs_pass1_tail:
    cmp     eax, esi
    jge     .cs_pass1_done
    vmovss  xmm3, [rdi + rax*4]
    vaddss  xmm0, xmm0, xmm3       ; sum += arr[i]
    vminss  xmm1, xmm1, xmm3       ; min = min(min, arr[i])
    vmaxss  xmm2, xmm2, xmm3       ; max = max(max, arr[i])
    inc     eax
    jmp     .cs_pass1_tail

.cs_pass1_done:
    ; ============================================================
    ; CALCULAR MEDIA (guardar en xmm6 para preservarla)
    ; ============================================================
    vcvtsi2ss xmm4, xmm4, esi      ; xmm4 = (float)n
    vdivss  xmm6, xmm0, xmm4       ; xmm6 = sum / n = mean  ← GUARDAR EN xmm6

    ; Guardar mean en memoria
    vmovss  [r12], xmm6

    ; ============================================================
    ; SEGUNDA PASADA VECTORIZADA: sum_sq = Σ(x - mean)²
    ; ============================================================
    vxorps  ymm0, ymm0, ymm0       ; ymm0 = sum_sq = 0

    ; Broadcast de mean (xmm6) a los 8 carriles.
    ; OJO: se usa ymm7, NO ymm4/xmm4, porque xmm4 todavia guarda (float)n
    ; y se necesita intacto para "var = sum_sq / n" en .cs_pass2_done.
    vbroadcastss ymm7, xmm6        ; ymm7 = mean (8 carriles)

    xor     eax, eax               ; eax = i = 0
    mov     ecx, esi
    and     ecx, ~7

    test    ecx, ecx
    jle     .cs_pass2_reduce

.cs_pass2_loop:
    cmp     eax, ecx
    jge     .cs_pass2_reduce
    vmovups ymm5, [rdi + rax*4]    ; ymm5 = arr[i..i+7]
    vsubps  ymm5, ymm5, ymm7       ; diff = arr - mean
    vmulps  ymm5, ymm5, ymm5       ; diff²
    vaddps  ymm0, ymm0, ymm5       ; sum_sq += diff²
    add     eax, 8
    jmp     .cs_pass2_loop

.cs_pass2_reduce:
    ; --- Reduccion horizontal de sum_sq ---
    vextractf128 xmm5, ymm0, 1
    vaddps  xmm0, xmm0, xmm5
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0       ; xmm0[0] = sum_sq total

    ; --- Bucle escalar de cierre ---
.cs_pass2_tail:
    cmp     eax, esi
    jge     .cs_pass2_done
    vmovss  xmm5, [rdi + rax*4]
    vsubss  xmm5, xmm5, xmm6       ; ← usar xmm6 (mean preservada)
    vmulss  xmm5, xmm5, xmm5
    vaddss  xmm0, xmm0, xmm5
    inc     eax
    jmp     .cs_pass2_tail

.cs_pass2_done:
    ; ============================================================
    ; CALCULAR VARIANZA Y GUARDAR RESULTADOS
    ; ============================================================
    vdivss  xmm0, xmm0, xmm4       ; var = sum_sq / n  (SOLO UNA VEZ)

    vmovss  [r13], xmm0            ; *var = var
    vmovss  [r14], xmm1            ; *min = min
    vmovss  [r15], xmm2            ; *max = max

    ; --- Restaurar registros y retornar ---
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    vzeroupper
    ret

.cs_error_n_zero:
    ; Si n == 0, poner todos los resultados a 0.0
    vxorps  xmm0, xmm0, xmm0
    vmovss  [rdx], xmm0            ; mean = 0
    vmovss  [rcx], xmm0            ; var = 0
    vmovss  [r8], xmm0             ; min = 0
    vmovss  [r9], xmm0             ; max = 0
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    vzeroupper
    ret


; ---------------------------------------------------------------
; void normalize_array(const float *in, float *out, int n,
;                       float mean, float stddev)
;   rdi = in, rsi = out, edx = n, xmm0 = mean, xmm1 = stddev
;
;   out[i] = (in[i] - mean) / stddev
;   Caso borde: si stddev == 0.0, copie in[i] en out[i] tal cual.
; ---------------------------------------------------------------
normalize_array:
    ; --- Guardar registros callee-saved ---
    push    rbx
    push    r12
    push    r13

    ; --- Validar n > 0 ---
    test    edx, edx
    jz      .na_done

    ; --- Verificar stddev == 0 ---
    vxorps  xmm2, xmm2, xmm2
    vucomiss xmm1, xmm2
    je      .na_zero_stddev

    ; ============================================================
    ; CASO NORMAL: Normalizar cada elemento
    ; ============================================================
    ; Broadcast de mean y stddev a YMM
    vbroadcastss ymm0, xmm0        ; ymm0 = mean (8 carriles)
    vbroadcastss ymm1, xmm1        ; ymm1 = stddev (8 carriles)

    mov     rbx, rdi               ; rbx = in
    mov     r12, rsi               ; r12 = out
    xor     eax, eax               ; eax = i = 0
    mov     ecx, edx
    and     ecx, ~7                ; ecx = n redondeado a multiplo de 8

    test    ecx, ecx
    jle     .na_norm_tail

.na_norm_loop:
    cmp     eax, ecx
    jge     .na_norm_tail
    vmovups ymm3, [rbx + rax*4]    ; carga 8 floats
    vsubps  ymm3, ymm3, ymm0       ; (in - mean)
    vdivps  ymm3, ymm3, ymm1       ; / stddev
    vmovups [r12 + rax*4], ymm3    ; guarda 8 floats
    add     eax, 8
    jmp     .na_norm_loop

.na_norm_tail:
    ; --- Bucle escalar de cierre para el remanente ---
    cmp     eax, edx
    jge     .na_done
    vmovss  xmm3, [rbx + rax*4]
    vsubss  xmm3, xmm3, xmm0
    vdivss  xmm3, xmm3, xmm1
    vmovss  [r12 + rax*4], xmm3
    inc     eax
    jmp     .na_norm_tail

.na_zero_stddev:
    ; ============================================================
    ; CASO ESPECIAL: stddev == 0 → copiar sin modificar
    ; ============================================================
    mov     rbx, rdi
    mov     r12, rsi
    xor     eax, eax
    mov     ecx, edx
    and     ecx, ~7

    test    ecx, ecx
    jle     .na_copy_tail

.na_copy_loop:
    cmp     eax, ecx
    jge     .na_copy_tail
    vmovups ymm3, [rbx + rax*4]
    vmovups [r12 + rax*4], ymm3
    add     eax, 8
    jmp     .na_copy_loop

.na_copy_tail:
    cmp     eax, edx
    jge     .na_done
    vmovss  xmm3, [rbx + rax*4]
    vmovss  [r12 + rax*4], xmm3
    inc     eax
    jmp     .na_copy_tail

.na_done:
    pop     r13
    pop     r12
    pop     rbx
    vzeroupper
    ret
