# Every runtime error explanation needs one result representation

The end-of-input method returns text, but the device-failure method returns an
integer. A caller cannot know which representation it will receive. Compilation
rejects the join; repair the second method to return a text message as well.

Success payloads plus native errors can form an error union. Arbitrary unrelated
successful result types do not gain an implicit union or conversion.
