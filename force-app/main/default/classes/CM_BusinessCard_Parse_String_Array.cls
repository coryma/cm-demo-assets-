public with sharing class CM_BusinessCard_Parse_String_Array {

    public class Input {
        @InvocableVariable(required=true) public String json; // e.g. '["068...","068..."]' or '068...'
    }
    public class Output {
        @InvocableVariable public List<String> values;
    }

    @InvocableMethod(label='Parse JSON String Array to Text Collection')
    public static List<Output> run(List<Input> inputs) {
        List<Output> outs = new List<Output>();
        for (Input i : inputs) {
            List<String> arr = new List<String>();
            String s = String.isBlank(i.json) ? '[]' : i.json.trim();
            try {
                Object o = (Object) JSON.deserializeUntyped(s);
                if (o instanceof List<Object>) {
                    for (Object v : (List<Object>)o) if (v != null) arr.add(String.valueOf(v));
                } else if (o instanceof String) {
                    arr.add((String)o);
                }
            } catch (Exception e) {
                // Fallback: if not valid JSON, treat as a single string
                arr.add(s);
            }
            Output out = new Output(); out.values = arr; outs.add(out);
        }
        return outs;
    }
}