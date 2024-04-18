! Copyright (c) 2024 Vaughan Kitchen
! Minimalistic BM25 search engine.

module dynarray_integer_mod
        implicit none
        private

        type, public :: dynarray_integer_class
                integer :: capacity, length
                integer(kind=4), allocatable :: store(:)
        contains
                procedure, public :: init => dynarray_integer_init
                procedure, public :: append => dynarray_integer_append
                procedure, public :: size => dynarray_integer_size
                procedure, public :: at => dynarray_integer_at
                procedure, public :: inc => dynarray_integer_inc
                procedure, public :: print => dynarray_integer_print
                procedure, public :: write => dynarray_integer_write
        end type dynarray_integer_class

contains
        subroutine dynarray_integer_init(this)
                class(dynarray_integer_class), intent(inout) :: this

                this%capacity = 128
                this%length = 0
                allocate(this%store(this%capacity))
        end subroutine dynarray_integer_init

        subroutine dynarray_integer_append(this, val)
                class(dynarray_integer_class), intent(inout) :: this
                integer(kind=4), intent(in) :: val
                integer(kind=4), allocatable :: buffer(:)

                ! Double the capacity if we've hit the limit
                if (this%length == this%capacity) then
                        call move_alloc(this%store, buffer)
                        this%capacity = this%capacity * 2
                        allocate(this%store(this%capacity))
                        this%store(1:this%length) = buffer
                        deallocate(buffer)
                end if

                this%length = this%length + 1
                this%store(this%length) = val
        end subroutine dynarray_integer_append

        function dynarray_integer_size(this) result(out)
                class(dynarray_integer_class), intent(inout) :: this
                integer :: out

                out = this%length
        end function dynarray_integer_size

        ! Access helper with negative indices for access from end of array
        function dynarray_integer_at(this, i) result(out)
                class(dynarray_integer_class), intent(inout) :: this
                integer, intent(in) :: i
                integer :: out

                if (i < 0) then
                        out = this%store(this%length + 1 + i)
                else
                        out = this%store(i)
                end if
        end function dynarray_integer_at

        ! Helper function to increment an element (we can because this is our own data structure)
        subroutine dynarray_integer_inc(this, i)
                class(dynarray_integer_class), intent(inout) :: this
                integer, intent(in) :: i

                if (i < 0) then
                        this%store(this%length + 1 + i) = this%store(this%length + 1 + i) + 1
                else
                        this%store(i) = this%store(i) + 1
                end if
        end subroutine dynarray_integer_inc

        subroutine dynarray_integer_print(this)
                class(dynarray_integer_class), intent(inout) :: this
                integer :: i

                do i = 1, this%length
                        print *, this%store(i)
                end do
        end subroutine dynarray_integer_print

        ! Write the array as contiguous bytes for 'lengths.bin' or 'postings.bin'
        subroutine dynarray_integer_write(this, fh)
                class(dynarray_integer_class), intent(inout) :: this
                integer, intent(in) :: fh

                write (fh) this%store(:this%length)
        end subroutine dynarray_integer_write
end module dynarray_integer_mod

module dynarray_string_mod
        implicit none
        private

        type, public :: dynarray_string_class
                integer :: capacity, length
                character(len=255), allocatable :: store(:)
        contains
                procedure, public :: init => dynarray_string_init
                procedure, public :: append => dynarray_string_append
                procedure, public :: print => dynarray_string_print
                procedure, public :: write => dynarray_string_write
        end type dynarray_string_class

contains
        subroutine dynarray_string_init(this)
                class(dynarray_string_class), intent(inout) :: this

                this%capacity = 128
                this%length = 0
                allocate(this%store(this%capacity))
        end subroutine dynarray_string_init

        subroutine dynarray_string_append(this, val)
                class(dynarray_string_class), intent(inout) :: this
                character(len=*), intent(in) :: val
                character(len=255), allocatable :: buffer(:)

                ! Double the capacity if we've hit the limit
                if (this%length == this%capacity) then
                        call move_alloc(this%store, buffer)
                        this%capacity = this%capacity * 2
                        allocate(this%store(this%capacity))
                        this%store(1:this%length) = buffer
                        deallocate(buffer)
                end if

                this%length = this%length + 1
                this%store(this%length) = val
        end subroutine dynarray_string_append

        subroutine dynarray_string_print(this)
                class(dynarray_string_class), intent(inout) :: this
                integer :: i

                do i = 1, this%length
                        print *, this%store(i)
                end do
        end subroutine dynarray_string_print

        ! Write the array as newline terminated strings for 'docids.bin'
        subroutine dynarray_string_write(this, fh)
                class(dynarray_string_class), intent(inout) :: this
                integer, intent(in) :: fh
                integer :: i

                do i = 1, this%length
                        write (fh) this%store(i)(1:len_trim(this%store(i)))
                        write (fh) new_line('A')
                end do
        end subroutine dynarray_string_write
end module dynarray_string_mod

module vocab_mod
        use dynarray_integer_mod
        implicit none
        private

        ! Fortran doesn't allow array of pointers
        type :: pair
                character(len=:), allocatable :: term
                type(dynarray_integer_class) :: postings
        end type pair


        type, public :: vocab_class
                integer :: capacity, length
                type(pair), allocatable :: store(:)
        contains
                procedure, public :: init => vocab_init
                procedure, private :: expand => vocab_expand
                procedure, public :: add => vocab_add
                procedure, public :: print => vocab_print
                procedure, public :: write => vocab_write
        end type vocab_class

contains
        ! djb2 hash function from http://www.cse.yorku.ca/~oz/hash.html
        function hash(str, cap) result(out)
                character(len=*), intent(in) :: str
                integer, intent(in) :: cap
                integer :: out
                integer :: i

                out = 5381

                do i = 1, len(str)
                        out = mod(ishft(out, 5) + out + ichar(str(i:i)), cap) ! hash * 33 + c
                end do
        end function hash

        subroutine vocab_init(this)
                class(vocab_class) :: this

                this%capacity = 128
                this%length = 0
                allocate(this%store(0:this%capacity-1)) ! 0 indexed store
        end subroutine vocab_init

        subroutine vocab_expand(this)
                class(vocab_class), intent(inout) :: this
                type(pair), allocatable :: buffer(:)
                integer :: old_cap, i, j

                ! Create new store with double the capacity
                old_cap = this%capacity
                this%capacity = this%capacity * 2

                call move_alloc(this%store, buffer)
                allocate(this%store(0:this%capacity-1))

                ! Rehash the old values and insert them again
                do i = 0, old_cap-1
                        if (.NOT. allocated(buffer(i)%term)) cycle

                        j = hash(buffer(i)%term, this%capacity)

                        do while (allocated(this%store(j)%term))
                                j = mod(j + 1, this%capacity)
                        end do

                        this%store(j) = buffer(i)
                end do

                deallocate(buffer)
        end subroutine vocab_expand

        subroutine vocab_add(this, term, docid)
                class(vocab_class), intent(inout) :: this
                character(len=*), intent(in) :: term
                integer, intent(in) :: docid
                integer :: i

                if (this%length * 2 > this%capacity) call this%expand()

                i = hash(term, this%capacity)

                ! Linear probe until we find somewhere to insert
                do while (allocated(this%store(i)%term))
                        if (this%store(i)%term == term) then
                                ! If the docno for this occurence has changed then create a new <d,tf> pair
                                if (this%store(i)%postings%at(-2) /= docid) then
                                        call this%store(i)%postings%append(docid)
                                        call this%store(i)%postings%append(1)
                                        return
                                end if
                                ! Else increase the tf
                                call this%store(i)%postings%inc(-1)
                                return
                        end if
                        i = mod(i + 1, this%capacity)
                end do

                ! If the term isn't in the vocab yet
                this%store(i)%term = term
                call this%store(i)%postings%init()
                call this%store(i)%postings%append(docid)
                call this%store(i)%postings%append(1)

                this%length = this%length + 1
        end subroutine vocab_add

        subroutine vocab_print(this)
                class(vocab_class), intent(inout) :: this
                integer :: i

                do i = 1, this%capacity
                        if (allocated(this%store(i)%term)) then
                                print '(A)', this%store(i)%term
                                call this%store(i)%postings%print()
                        end if
                end do
        end subroutine vocab_print

        ! Write the HashTable as int8, char(:), '\0', int32, int32 for 'vocab.bin'
        subroutine vocab_write(this, vocab_fh, postings_fh)
                class(vocab_class), intent(inout) :: this
                integer, intent(in) :: vocab_fh, postings_fh
                integer :: where, i

                do i = 0, this%capacity-1
                        if (allocated(this%store(i)%term)) then
                                ! Write the postings list to one file
                                inquire (unit=postings_fh, size=where)
                                call this%store(i)%postings%write(postings_fh)

                                ! Write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
                                write (vocab_fh) int(len_trim(this%store(i)%term), 1)
                                write (vocab_fh) this%store(i)%term(1:len_trim(this%store(i)%term))
                                write (vocab_fh) int(0, 1)
                                write (vocab_fh) where
                                write (vocab_fh) this%store(i)%postings%size() * 4 ! in bytes
                        end if
                end do
        end subroutine vocab_write
end module vocab_mod

module lexer_mod
        implicit none
        private

        ! Class lexer
        type, public :: lexer_class
                integer :: length, current
                character(len=:), allocatable :: buffer
        contains
                procedure, public :: init => lexer_init
                procedure, public :: get_next => lexer_get_next
        end type lexer_class

contains
        function is_alnum(c) result(out)
                character(len=1), intent(in) :: c
                logical :: out

                select case (ichar(c))
                        case (48:57) ! numeric
                                out = .TRUE.
                        case (65:90) ! capital letters
                                out = .TRUE.
                        case (97:122) ! lowercase letters
                                out = .TRUE.
                        case default
                                out = .FALSE.
                end select
        end function is_alnum

        subroutine lexer_init(this, buffer, buffer_length)
                class(lexer_class), intent(inout) :: this
                character(len=*), intent(in) :: buffer
                integer, intent(in) :: buffer_length

                this%buffer = buffer
                this%current = 1
                this%length = buffer_length
        end subroutine lexer_init

        ! One-character lookahead lexical analyser
        function lexer_get_next(this, rc) result(out)
                class(lexer_class), intent(inout) :: this
                integer, intent(inout) :: rc
                character(len=:), allocatable :: out
                integer :: start

                ! Skip over whitespace and punctuation (but not XML tags)
                do while (this%current <= this%length .AND. .NOT. is_alnum(this%buffer(this%current:this%current)) &
                .AND. this%buffer(this%current:this%current) /= '<')
                        this%current = this%current + 1
                end do

                ! A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
                start = this%current
                if (this%current > this%length) then
                        rc = -1
                        return
                else if (is_alnum(this%buffer(this%current:this%current))) then
                        do while (this%current <= this%length .AND. (is_alnum(this%buffer(this%current:this%current)) &
                        .OR. this%buffer(this%current:this%current) == '-'))
                                this%current = this%current + 1
                        end do
                else if (this%buffer(this%current:this%current) == '<') then
                        this%current = this%current + 1
                        do while (this%current <= this%length .AND. this%buffer(this%current-1:this%current-1) /= '>')
                                this%current = this%current + 1
                        end do
                end if

                ! Copy and return the token
                out = this%buffer(start:this%current-1)
        end function lexer_get_next
end module lexer_mod

program index
        use dynarray_integer_mod
        use dynarray_string_mod
        use lexer_mod
        use vocab_mod
        implicit none

        type(lexer_class) :: lexer
        type(vocab_class) :: vocab
        type(dynarray_string_class) :: doc_ids
        type(dynarray_integer_class) :: doc_lengths
        integer :: argc, docid, document_length
        integer :: rc ! return code
        logical :: push_next
        character(len=2048) :: buffer ! fortran memsets the buffer on every read so don't make it too big
        integer :: buffer_length
        character(len=:), allocatable :: token

        ! Make sure we have one parameter, the filename
        argc = command_argument_count()
        if (argc /= 1) then
                call get_command_argument(0, buffer)
                print '(A)', 'Usage: ' // buffer(1:len_trim(buffer)) // ' <infile.xml>'
                stop
        end if

        ! Open the file to index
        call get_command_argument(1, buffer)
        open (unit=10, action='read', file=buffer(1:len_trim(buffer)), iostat=rc)
        if (rc /= 0) stop 'ERROR: open failed'

        ! Init
        docid = -1
        document_length = 0
        push_next = .FALSE.
        call vocab%init()
        call doc_ids%init()
        call doc_lengths%init()

        ! Read the file line by line
        do
                read (10, '(A)', iostat=rc, size=buffer_length, advance='no') buffer
                if (is_iostat_end(rc)) exit
                rc = 0
                call lexer%init(buffer, buffer_length)
                ! Read the line token by token
                do
                        token = lexer%get_next(rc)
                        if (rc /= 0) exit
                        ! If we see a <DOC> tag then we're at the start of the next document
                        if (token == '<DOC>') then
                                ! Save the previous document length
                                if (docid /= -1) call doc_lengths%append(document_length)
                                ! Move on to the next document
                                docid = docid + 1
                                document_length = 0
                                if (mod(docid, 1000) == 0) print '(I0, A)', docid, ' documents indexed'
                        end if
                        ! if the last token we saw was a <DOCNO> then the next token is the primary key
                        if (push_next) then
                                call doc_ids%append(token)
                                push_next = .FALSE.
                        end if
                        if (token == '<DOCNO>') push_next = .TRUE.
                        ! Don't index XML tags
                        if (token(1:1) == '<') cycle
                        ! Lowercase the string
                        call lowercase(token)
                        ! Truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
                        if (len(token) > 255) token = token(1:255)
                        ! Add the posting to the in-memory index
                        call vocab%add(token, docid)
                        ! Compute the document length
                        document_length = document_length + 1
                end do
        end do

        ! If we didn't index any documents then we're done.
        if (docid == -1) stop

        ! Save the final document length
        call doc_lengths%append(document_length)

        ! Tell the user we've got to the end of parsing
        print '(A, I0, A)', 'Indexed ', docid + 1, ' documents. Serialising...'

        ! Store the primary keys
        open (unit=11, action='write', file='docids.bin', iostat=rc, status='replace', access='stream')
        if (rc /= 0) stop 'ERROR: open failed'
        call doc_ids%write(11)

        ! Serialise the in-memory index to disk
        open (unit=12, action='write', file='vocab.bin', iostat=rc, status='replace', access='stream')
        if (rc /= 0) stop 'ERROR: open failed'
        open (unit=13, action='write', file='postings.bin', iostat=rc, status='replace', access='stream')
        if (rc /= 0) stop 'ERROR: open failed'
        call vocab%write(12, 13)

        ! Store the document lengths
        open (unit=14, action='write', file='lengths.bin', iostat=rc, status='replace', access='stream')
        if (rc /= 0) stop 'ERROR: open failed'
        call doc_lengths%write(14)

        ! Clean up
        close (10)
        close (11)
        close (12)
        close (13)
        close (14)
contains
        subroutine lowercase(str)
                character(len=*), intent(inout) :: str
                integer :: i

                do i = 1, len(str)
                        if ('A' <= str(i:i) .AND. str(i:i) <= 'Z') str(i:i) = char(ichar(str(i:i)) + 32)
                end do
        end subroutine lowercase
end program index
