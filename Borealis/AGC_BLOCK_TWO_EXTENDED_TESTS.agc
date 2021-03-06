### FILE="Main.annotation"
## Copyright:   Public domain.
## Filename:    AGC_BLOCK_TWO_EXTENDED_TESTS.agc
## Purpose:     This program is designed to extensively test the Apollo Guidance Computer
##              (specifically the LM instantiation of it). It is built on top of a heavily
##              stripped-down Aurora 12, with all code ostensibly added by the DAP Group
##              removed. Instead Borealis expands upon the tests provided by Aurora,
##              including corrected tests from Retread 44 and tests from Ron Burkey's
##              Validation.
## Assembler:   yaYUL
## Contact:     Mike Stewart <mastewar1@gmail.com>.
## Website:     www.ibiblio.org/apollo/index.html
## Mod history: 2017-01-15 MAS  Created to hold new extended tests, starting off with
##                              checking out all the timers, EDRUPT, BRUPT substitution,
##                              and interrupts following an INDEX.
##              2017-09-03 MAS  Added in some tests for proper handling of Z and ZRUPT.
##                              The ZRUPT test makes use of EDRUPT again, so that gets
##                              more thoroughly tested too.
##              2017-09-04 MAS  Rewrote the new ZRUPT test to simply RESUME outside of an
##                              interrupt instead of using EDRUPT. This saves a few words,
##                              and exercises RESUME's ability to work whenever.

                BANK            24
# The extended tests check out functionalities not exercised by the Aurora or Retread tests. First up
# is testing of the interrupt priority chain (insofar as it can be deterministically and automatically
# checked) by queuing up all four timer interrupts, and then executing them one at a time using EDRUPT.

# What we're about to do is sensitive to the phasing of TIME3. Instead of risking it, we simply wait
# for the next TIME3 increment so we can be sure we're safe.
EXTTESTS        CA              TIME3
                TS              SKEEP1
WAITT3          CS              TIME3                           # Wait for the next TIME3 increment.
                AD              SKEEP1                          # No TCs are needed due to a bug in
                EXTEND                                          # the TC alarm hardware.
                BZF             WAITT3

# With phasing correct, inhibit interrupts and trigger all the timers.
                INHINT

SCHEDT6         CAF             LOW4                            # Start with TIME6. It counts the fastest,
                TS              TIME6                           # and will provide a bounds after which we'll
                CAF             BIT15                           # know all the others have fired.
                EXTEND
                WOR             CHAN13                          # Start the timer for a bit over 10ms. This
                                                                # bit resetting will tell us we're done.

SCHEDT5         CAF             POSMAX                          # Schedule T5RUPT to happen in <=10ms.
                TS              TIME5

SCHEDT3         CAF             ONE                             # Schedule a T3RUPT by waitlisting a task
                TC              WAITLIST                        # that does nothing to execute ASAP.
                2CADR           NOTHING

# TIME4 needs a bit of special handling. It expects to execute periodically and naively forcing it to
# happen sooner could throw off display handling or other things. Instead, we'll only accelerate it
# if necessary, and if so make sure it doesn't do any actual work in the accelerated interrupt.
SCHEDT4         CCS             TIME4                           # Check to see if we need to force TIME4.
                TCF             +2                              # TIME4 positive, we may need to accelerate.
                TCF             T6CHK                           # TIME4 is zero, so T4RUPT is already pending
                AD              TWO                             # Calculate the new TIME4 value (+10ms from old)
                OVSK                                            # ... and if that overflows, TIME4 is already going
                TCF             +2                              # to happen as quickly as is possible, so we can
                TCF             T6CHK                           # just leave it alone.
                TS              T4TEMP                          # Save the adjusted original TIME4 value so T4RUPT
                CA              POSMAX                          # can reschedule, and then set T4RUPT to occur in
                TS              TIME4                           # <= 10ms.

# All of the balls are now rolling, so we can now wait for TIME6 to expire. While doing so, we can
# verify that TIME6 and the DINC sequence behave as expected.
T6CHK           CCS             TIME6                           # Wait for TIME6 to hit -0
                TCF             T6CHK
                TC              ERRORS                          # (NOT +0, is skipped over)
                TC              ERRORS
                CS              BIT15                           # TIME6 has reached -0. It is, hover, still active,
                EXTEND                                          # because DINC doesn't trigger ZOUT (needed for
                ROR             CHAN13                          # T6RUPT) until it occurs when its counter is already
                TC              -0CHK                           # +-0. Thus, T6 should still be enabled.

# We can now waste a bit of time until the final TIME6 count occurs, and in doing so verify that
# it's counting at roughly the expected rate (1/1600 seconds). That translates to ~53.333 MCT. The
# following loops is timed such that from the "CS BIT15" above to to the "EXTEND" below there
# are exactly 54 MCTs (ignoring any counter increments).
                CAF             NINE
T6BUSYWT        NOOP
                CCS             A
                TCF             T6BUSYWT

                CAF             BIT15                           # T6 should now have switched itself off.
                EXTEND
                RAND            CHAN13
                TC              +0CHK

# At this point, we can safely expect all four timer interrupts to be pending. We can now
# test each one works, and that each has the correct priority, by executing four EDRUPTs
# and checking to see that the expected timer interrupt was serviced. The expected priority
# order is 6, 5, 3, 4.
PRIOCHK         CAF             SIX
                TC              TRIGRUPT
                CAF             FIVE
                TC              TRIGRUPT
                CAF             THREE
                TC              TRIGRUPT
                CAF             FOUR
                TC              TRIGRUPT

# Timers and their interrupts are healthy. It's finally safe to release interrupts.
                RELINT

# Check that bits set in the upper 4 bits of Z disappear between instructions, and that
# storing directly to Z behaves as expected.
ZCHK            CA              ZSKIPADR                        # Check proper operation of Z. Z should
                AD              SBIT13                          # generally shed anything in its upper
                TS              Z                               # 4 bits.
                TC              ERRORS                          # Storing to Z should take immediate effect.

ZSKIP           CS              Z                               # Make sure bit 13 disappeared.
                AD              ZSKIPADR
                TC              -1CHK

# The only exception to the above is RESUME. A RESUME moves the full contents of ZRUPT into Z, without
# truncating to the lower 12 bits. The next instruction executed after the RESUME (i.e., the one in
# BRUPT) can therefore see these upper bits of Z. This is the only time these bits' existence are
# detectable (outside of one particular DV case, which we will exercise shortly).
ZRUPTCHK        CA              ZRELADR                         # Piece together a value for ZRUPT with a
                AD              SBIT13                          # high-order bit set.
                INHINT                                          # Inhibit interrupts so we can safely
                TS              ZRUPT                           # touch ZRUPT and BRUPT.
                CA              ZSKIP                           # Replace BRUPT with "CS Z", which we will
                TS              BRUPT                           # use to sense the upper Z bits.
                RESUME                                          # RESUME, so BRUPT is executed and Z = ZRUPT
ZREL            RELINT                                          # Interrupts are safe now.
                AD              SBIT13
                AD              ZRELADR
                TC              -0CHK                           # ZRUPT should have been ZREL + SBIT13

# Head to bank 3, where all EDRUPT tests must take place.
                TC              BRUPTCHK

# Extended tests are complete. Head back to self-check proper.
                TC              POSTJUMP
                CADR            EXTTDONE

ZSKIPADR        ADRES           ZSKIP
ZRELADR         ADRES           ZREL

# Interrupt routine used in BRUPTCHK.
ARUPTVEC        DXCH            ARUPT                           # Although Q is also destroyed, we happen to know
                                                                # that the "interrupted" program doesn't need it.

                CS              BRUPT                           # Check that BRUPT was correctly calculated as 
                AD              EDRPTWRD                        # "EDRUPT BRUPTCHK +5".
                AD              FIVE
                TC              -0CHK

                CS              ZRUPT                           # ZRUPT should be pointing at the address
                AD              EDRP+1AD                        # immediately following the EDRUPT.
                TC              -0CHK

                CAF             BRUPTCHK                        # Break out of the EDRUPT loop by replacing
                TS              BRUPT                           # BRUPT with "CAF FIVE".
                TC              NOQBRSM

ARVECADR        ADRES           ARUPTVEC
EDRP+1AD        ADRES           EDRPT+1

# Do-nothing waitlist task, used as a dummy when generating a fast T3RUPT.
NOTHING         TC              TASKOVER

ENDEXTST        EQUALS

                SETLOC          ENDINTF
# Check EDRUPT's ability to vector to A with no pending interrupts, the correct
# behavior of BRUPT for interrupts following an INDEX, and BRUPT substitution.
BRUPTCHK        CAF             FIVE                            # SKEEP1 = 5. This will be used for indexing.
                TS              SKEEP1
                EXTEND                                          # Save our return address.
                QXCH            SKEEP2
                CAF             ARVECADR                        # Attempt to use EDRUPT to vector to ARUPTVEC.
 +5             EXTEND                                          # If some other interrupt is taken, continue
                INDEX           SKEEP1                          # at BRUPTCHK+5 (as calculated by the INDEX).
EDRPTWRD        EDRUPT          BRUPTCHK                        # This instruction should be replaced with
EDRPT+1         AD              NEG4                            # "CAF FIVE" upon resume. Make sure it did.
                TC              +1CHK

                TC              SKEEP2                          # All done here. Head back to SELF-CHECK proper.

# Routine to trigger a pending timer interrupt and verify that the timer whose number is
# specified in A was the one that got serviced.
TRIGRUPT        XCH             L
                EXTEND
                QXCH            SKEEP1
                CAF             ZERO                            # Zero LASTIMER so we don't get duped.
                TS              LASTIMER
                CA              NOPNDADR                        # EDRUPT will fall back on this vector if
                EXTEND                                          # no interrupts at all are pending.
                EDRUPT          TRPTCHK                         # Trigger an interrupt, then skip over TC ERRORS.
                TC              ERRORS
TRPTCHK         CS              LASTIMER                        # Check the timer that just got executed matches
                AD              L                               # what was expected.
                TC              -0CHK
                TC              SKEEP1

NOPNDING        TC              ERRORS
NOPNDADR        ADRES           NOPNDING

# T5 and T6 interrupt routines. Both currently only set LASTIMER for use with the extended self-tests.
T5RUPT          TS              BANKRUPT
                CAF             FIVE
                TS              LASTIMER
                TCF             NOQRSM

T6RUPT          TS              BANKRUPT
                CAF             SIX
                TS              LASTIMER
                TCF             NOQRSM

ENDSLFS4        EQUALS
