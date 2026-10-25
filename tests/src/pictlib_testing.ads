package Pictlib_Testing is
   pragma Pure;

   --  An opcode a failure must name, or Any_Opcode, which checks none: opcode 0, NOP, is an opcode too.
   subtype Expected_Opcode is Integer range -1 .. 16#FFFF#;
   Any_Opcode : constant Expected_Opcode := -1;
end Pictlib_Testing;
