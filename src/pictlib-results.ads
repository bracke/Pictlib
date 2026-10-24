with Pictlib.Errors;

package Pictlib.Results is
   pragma Preelaborate;

   type Status is (Ok, Failed);

   type Result is record
      State : Status := Ok;
      First_Error : Errors.Error := Errors.Make (Errors.No_Error);
   end record;

   --  Success.
   --  @return Operation result.
   function Success return Result is ((State => Ok, First_Error => Errors.Make (Errors.No_Error)));
   --  Failure.
   --  @param Code Error code reported with an empty diagnostic context.
   --  @return Operation result.
   function Failure (Code : Errors.Error_Code) return Result is
     ((State => Failed, First_Error => Errors.Make (Code)));
   --  Failure.
   --  @param Item Error reported as the first error.
   --  @return Operation result.
   function Failure (Item : Errors.Error) return Result is ((State => Failed, First_Error => Item));
   --  Succeeded.
   --  @param Item Result to inspect.
   --  @return True when Item reports success.
   function Succeeded (Item : Result) return Boolean is (Item.State = Ok);
end Pictlib.Results;
