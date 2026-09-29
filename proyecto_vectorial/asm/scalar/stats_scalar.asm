; ============================================================
; stats_scalar.asm - Versión escalar (SSE)
; Normalizador estadístico vectorizado
; Implementa: sum_array, compute_stats, normalize_array
; Convención: System V AMD64 ABI
; 
; Firmas según stats.h:
;   float sum_array(const float *arr, int n);
;   void compute_stats(const float *arr, int n, float *mean, float *var, 
;                      float *min, float *max);
;   void normalize_array(const float *in, float *out, int n, 
;                        float mean, float stddev);
;
; Compilación: nasm -f elf64 -g -F dwarf stats_scalar.asm -o stats_scalar.o
; ============================================================

section .text
global sum_array
global compute_stats
global normalize_array

; ============================================================
; float sum_array(const float *arr, int n)
;
; Argumentos:
;   rdi = arr (puntero al arreglo) - const float*
;   esi = n (número de elementos) - int
;
; Retorna:
;   xmm0 = suma total (float)
;
; Registros usados:
;   xmm0: acumulador de suma
;   xmm1: valor temporal cargado
;   rcx: contador
; ============================================================
sum_array:
    ; Inicializar acumulador a 0.0
    xorps xmm0, xmm0
    
    ; Verificar si n == 0
    test esi, esi
    jz .done
    
    ; Configurar contador
    mov rcx, rsi            ; rcx = n
    
.loop:
    ; Cargar arr[i] y sumar
    movss xmm1, [rdi]       ; xmm1 = arr[i]
    addss xmm0, xmm1        ; xmm0 += arr[i]
    
    ; Avanzar al siguiente elemento
    add rdi, 4              ; puntero += 4 bytes (sizeof(float))
    dec rcx                 ; contador--
    jnz .loop               ; si contador != 0, repetir
    
.done:
    ret


; ============================================================
; void compute_stats(const float *arr, int n, float *mean, float *var,
;                    float *min, float *max)
;
; Argumentos:
;   rdi = arr (puntero al arreglo) - const float*
;   esi = n (número de elementos) - int
;   rdx = mean (puntero donde guardar la media) - float*
;   rcx = var (puntero donde guardar la varianza) - float*
;   r8  = min (puntero donde guardar el mínimo) - float*
;   r9  = max (puntero donde guardar el máximo) - float*
;
; Nota: varianza POBLACIONAL: var = sum((x - mean)^2) / n
;       Si n == 0, escribir 0.0 en mean/var/min/max
;
; Registros usados:
;   rbx: puntero actual (callee-saved)
;   r12: n guardado (callee-saved)
;   r13: contador (callee-saved)
;   xmm0: sum (primera pasada) / sum_sq (segunda pasada)
;   xmm1: min
;   xmm2: max
;   xmm3: arr[i] / mean
;   xmm4: (float)n
;   xmm5: diff (arr[i] - mean)
; ============================================================
compute_stats:
    ; --- Guardar registros no volátiles (callee-saved) ---
    push rbx
    push r12
    push r13
    
    ; --- Validar n > 0 ---
    test esi, esi
    jz .error_n_zero        ; si n == 0, manejar error
    
    ; --- ===== PRIMER PASADA: sum, min, max ===== ---
    
    ; Inicializar acumuladores
    xorps xmm0, xmm0        ; xmm0 = 0.0 (sum)
    movss xmm1, [rdi]       ; xmm1 = arr[0] (min)
    movss xmm2, [rdi]       ; xmm2 = arr[0] (max)
    
    mov rbx, rdi            ; rbx = puntero actual (empieza en arr)
    mov r12, rsi            ; r12 = n (guardar para después)
    xor r13, r13            ; r13 = 0 (contador)
    
    ; Bucle de primera pasada
    cmp r12, 0
    je .primer_pasada_done
    
.primer_pasada_loop:
    movss xmm3, [rbx]       ; xmm3 = arr[i]
    
    ; sum += arr[i]
    addss xmm0, xmm3        ; xmm0 += arr[i]
    
    ; Actualizar mínimo: if (arr[i] < min) min = arr[i]
    comiss xmm3, xmm1       ; comparar arr[i] vs min
    jae .skip_min           ; if (arr[i] >= min) saltar
    movss xmm1, xmm3        ; min = arr[i]
.skip_min:
    
    ; Actualizar máximo: if (arr[i] > max) max = arr[i]
    comiss xmm3, xmm2       ; comparar arr[i] vs max
    jbe .skip_max           ; if (arr[i] <= max) saltar
    movss xmm2, xmm3        ; max = arr[i]
.skip_max:
    
    ; Avanzar al siguiente elemento
    add rbx, 4              ; puntero += 4
    inc r13                 ; contador++
    cmp r13, r12            ; comparar contador vs n
    jl .primer_pasada_loop  ; if (contador < n) repetir
    
.primer_pasada_done:
    
    ; --- ===== CALCULAR MEDIA ===== ---
    
    ; Convertir n a float
    cvtsi2ss xmm4, r12      ; xmm4 = (float)n
    
    ; mean = sum / n
    movss xmm3, xmm0        ; xmm3 = sum
    divss xmm3, xmm4        ; xmm3 = sum / n = mean
    
    ; Guardar mean en el puntero proporcionado
    movss [rdx], xmm3       ; *mean = mean
    
    ; --- ===== SEGUNDA PASADA: sum_sq = Σ(arr[i] - mean)² ===== ---
    
    ; Inicializar sum_sq a 0.0
    xorps xmm0, xmm0        ; xmm0 = 0.0 (sum_sq)
    
    ; Reiniciar puntero y contador
    mov rbx, rdi            ; rbx = arr (reiniciar)
    xor r13, r13            ; r13 = 0 (contador)
    
    ; Bucle de segunda pasada
    cmp r12, 0
    je .segunda_pasada_done
    
.segunda_pasada_loop:
    movss xmm5, [rbx]       ; xmm5 = arr[i]
    subss xmm5, xmm3        ; xmm5 = arr[i] - mean
    mulss xmm5, xmm5        ; xmm5 = (arr[i] - mean)²
    addss xmm0, xmm5        ; xmm0 += (arr[i] - mean)²
    
    ; Avanzar al siguiente elemento
    add rbx, 4              ; puntero += 4
    inc r13                 ; contador++
    cmp r13, r12            ; comparar contador vs n
    jl .segunda_pasada_loop ; if (contador < n) repetir
    
.segunda_pasada_done:
    
    ; --- ===== CALCULAR VARIANZA ===== ---
    
    ; var = sum_sq / n (varianza POBLACIONAL)
    divss xmm0, xmm4        ; xmm0 = sum_sq / n = var
    
    ; --- ===== GUARDAR RESULTADOS ===== ---
    
    movss [rcx], xmm0       ; *var = var (xmm0)
    movss [r8], xmm1        ; *min = min (xmm1)
    movss [r9], xmm2        ; *max = max (xmm2)
    
    ; --- Restaurar registros y retornar ---
    pop r13
    pop r12
    pop rbx
    ret
    
.error_n_zero:
    ; Si n == 0, poner todos los resultados a 0.0 (como pide el enunciado)
    xorps xmm0, xmm0        ; 0.0
    movss [rdx], xmm0       ; *mean = 0
    movss [rcx], xmm0       ; *var = 0
    movss [r8], xmm0        ; *min = 0
    movss [r9], xmm0        ; *max = 0
    
    ; Restaurar registros y retornar
    pop r13
    pop r12
    pop rbx
    ret


; ============================================================
; void normalize_array(const float *in, float *out, int n,
;                      float mean, float stddev)
;
; Argumentos:
;   rdi = in (puntero al arreglo de entrada) - const float*
;   rsi = out (puntero al arreglo de salida) - float*
;   edx = n (número de elementos) - int
;   xmm0 = mean (media) - float
;   xmm1 = stddev (desviación estándar) - float
;
; Nota: out[i] = (in[i] - mean) / stddev
;       Si stddev == 0.0, copiar in[i] en out[i] tal cual
;
; Registros usados:
;   rbx: puntero de entrada (callee-saved)
;   r12: puntero de salida (callee-saved)
;   rcx: contador
;   xmm0: mean (argumento)
;   xmm1: stddev (argumento)
;   xmm2: cero (0.0) para comparación
;   xmm3: valor temporal
; ============================================================
normalize_array:
    ; --- Guardar registros no volátiles (callee-saved) ---
    push rbx
    push r12
    
    ; --- Validar n > 0 ---
    test edx, edx
    jz .done                ; si n == 0, retornar
    
    ; --- Verificar si stddev == 0 ---
    xorps xmm2, xmm2        ; xmm2 = 0.0
    comiss xmm1, xmm2       ; comparar stddev con 0.0
    je .zero_stddev         ; si stddev == 0, copiar sin normalizar
    
    ; --- ===== CASO NORMAL: Normalizar cada elemento ===== ---
    ;   out[i] = (in[i] - mean) / stddev
    
    mov rbx, rdi            ; rbx = in (puntero entrada)
    mov r12, rsi            ; r12 = out (puntero salida)
    mov rcx, rdx            ; rcx = n (contador)
    
.norm_loop:
    ; Cargar in[i]
    movss xmm3, [rbx]       ; xmm3 = in[i]
    
    ; Calcular (in[i] - mean) / stddev
    subss xmm3, xmm0        ; xmm3 = in[i] - mean
    divss xmm3, xmm1        ; xmm3 = (in[i] - mean) / stddev
    
    ; Guardar en out[i]
    movss [r12], xmm3       ; out[i] = xmm3
    
    ; Avanzar al siguiente elemento
    add rbx, 4              ; puntero entrada += 4
    add r12, 4              ; puntero salida += 4
    dec rcx                 ; contador--
    jnz .norm_loop          ; si contador != 0, repetir
    
    jmp .done
    
.zero_stddev:
    ; --- ===== CASO ESPECIAL: stddev == 0 ===== ---
    ;   Copiar entrada a salida sin cambios (evitar división por cero)
    
    mov rbx, rdi            ; rbx = in (puntero entrada)
    mov r12, rsi            ; r12 = out (puntero salida)
    mov rcx, rdx            ; rcx = n (contador)
    
.copy_loop:
    ; Cargar in[i]
    movss xmm3, [rbx]       ; xmm3 = in[i]
    
    ; Guardar directamente en out[i] (sin modificar)
    movss [r12], xmm3       ; out[i] = in[i]
    
    ; Avanzar al siguiente elemento
    add rbx, 4              ; puntero entrada += 4
    add r12, 4              ; puntero salida += 4
    dec rcx                 ; contador--
    jnz .copy_loop          ; si contador != 0, repetir
    
.done:
    ; --- Restaurar registros y retornar ---
    pop r12
    pop rbx
    ret
