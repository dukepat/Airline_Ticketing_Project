// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;
pragma experimental ABIEncoderV2;

import './Utility.sol';
import './Ticket.sol';

contract Airline {
    // Flight structure
    struct Flight{
       string flightName;
       // flightInstanceIdentifier = flightRoute+scheduledDeparture
       string flightInstanceIdentifier;
       uint scheduledDeparture;
       uint scheduledArrival;
       uint actualDeparture;
       uint actualArrival;
       flightState flightStatus;
       uint availableSeats;
       uint arrayIndex;
    }
    string airlineName;
    // Owner account of the airline, which wil be set during the deployment
    // Note: Only owner can invoke "OwnerOnly" functions
    address owner;
    enum flightState {Scheduled, Ontime, Delayed, Cancelled, Completed}
    // below is mapping[Flight.flightInstanceIdentifier] =>Ticket[]
    // Will be used to effect airline operations for all tickets booked for the specific flight
    mapping(string => Ticket[]) m_flightTotalTicket;
    //Operable flights in existence
    //Mapping List of all flights with schedules for a period for which the bookings can be made by the customer
    Flight[] scheduledFlights;      


    uint CancelPenalty2H_4H_Per = 70;
    uint CancelPenalty4H_8H_Per = 20;
    
    event AirlineEvent (
      string Message
    );

    event TicketEvent (
      address TicketAddress
    );
 
    bool isScheduled = false;  
     // Local variables
    string[]  _from = ['BLR','BOM','HYD','MAA'];
    string[]  _to = ['DEL','BLR','BLR','BLR'];
    constructor(string memory _airlineName){
        airlineName = _airlineName;
        // set the owner (Account which deployed this contract)
        owner = msg.sender;    
    }
    // Internal function to refresh scheduled flights array to have flight's latest status
    function refreshFlights(Flight memory _flight) internal {
        scheduledFlights[scheduledFlights.length - 1].arrayIndex = _flight.arrayIndex;
        scheduledFlights[_flight.arrayIndex] =  scheduledFlights[scheduledFlights.length - 1];
        scheduledFlights.pop();
        _flight.arrayIndex = scheduledFlights.length;
        scheduledFlights.push(_flight);
    }
    // Internal function to find the flight
    function findFlightNotCancelledCompleted(string memory _flightID) internal view returns(Flight memory){
        Flight memory foundFlight;
        foundFlight = findFlight (_flightID);
        if(foundFlight.flightStatus == flightState.Completed || foundFlight.flightStatus == flightState.Cancelled){
            revert(string(abi.encodePacked("**  Error  ** : Requested Flight :: ",_flightID,":: IS COMPLETED or CANCELLED")));
        } 
        return(foundFlight);
    }
    // Internal function used by book ticket action, if all validation pass will return the flight's departure time
    function isScheduledAndHaveSeats(string memory _flightID, uint _seats) internal returns(uint scheduledDepartureTime,uint actualDepartureTime, uint flightStatus){
        Flight memory foundFlight;
        // 1st check: Whether there is an existing scheduled flight for the given flight id 
        // 2nd check: Even if there is a scheduled flight, check if it is not already completed or cancelled 
        foundFlight = findFlightNotCancelledCompleted(_flightID);
        // 3rd check: Even if there is future flight, check if there are available seats
        if(foundFlight.availableSeats < _seats){
            emit AirlineEvent(string(abi.encodePacked("**  Error  ** :: ",_flightID,"::DOES NOT HAVE ENOUGH SEATS.", " Currently availble seats:: ",uint8(foundFlight.availableSeats)%10+48)));
            revert(string(abi.encodePacked("**  Error  ** :: ",_flightID,"::DOES NOT HAVE ENOUGH SEATS.", " Currently availble seats:: ",uint8(foundFlight.availableSeats)%10+48)));
        }
        foundFlight.availableSeats = (foundFlight.availableSeats - _seats);
        refreshFlights(foundFlight);
        return (foundFlight.scheduledDeparture, foundFlight.actualDeparture,(uint(foundFlight.flightStatus)));
    }
    // Customer interface to get the list of Operable Flights
    function getOperableFlights() view external returns (string memory){
       string memory _flights;
       uint i = 0;
       for (i = 0; i < scheduledFlights.length; i++) {
            _flights = string(abi.encodePacked(_flights,"  [",scheduledFlights[i].flightInstanceIdentifier,"]  "));
        }
        return _flights;
    }
    // Customer interface to book ticket
    function bookTicket(address _customer, string memory _flightID, uint _seats, uint _transferAmount, string memory _bookingRef) external returns(address){
        (uint scheduledDepartureTime,uint actualDepartureTime, uint flightStatus)  = isScheduledAndHaveSeats(_flightID,_seats); 
        Ticket ticket = new Ticket(_customer,_flightID,_bookingRef,_seats,_transferAmount,scheduledDepartureTime,actualDepartureTime,flightStatus);
        m_flightTotalTicket[_flightID].push(ticket);
        emit TicketEvent(address(ticket));
        return(address(ticket));
    }
    // Customer interface to cancel ticket
    // Incorporates the penalty clauses on the cancellations
    // Check whether the customer claim post travel, if the airline not have updated the final status  
    function customerCancelTicket( address _ticketAddress, uint _timeDifference, bool _isAfter) external returns(uint penalty) {
        Ticket ticket = Ticket(payable(_ticketAddress));
        Flight memory foundFlight;
        uint penaltyPercentage = 0;
        foundFlight = findFlightNotCancelledCompleted(ticket.getTicketFlightID());
        // If customer request claim after departure time check below,
        // 1.24 hours had past since the departure of the flight
        // 2.whether airline had updated the final status 
        if (_isAfter == true && _timeDifference <= 24 hours ){
            emit AirlineEvent("Error: Ticket cancellation cannot be done, need to wait for 24 hours for flight status update");
            revert("Error: Ticket cancellation cannot be done, need to wait for 24 hours for flight status update");
        }
        else if(_isAfter == false){ 
            if(_timeDifference < 2 hours){
                penaltyPercentage = 100;
            }else if(_timeDifference >= 2 hours && _timeDifference <= 4 hours ){
                penaltyPercentage = CancelPenalty2H_4H_Per;
            }
            else if(_timeDifference > 4 hours && _timeDifference <= 8 hours){
                penaltyPercentage = CancelPenalty4H_8H_Per;
            }
        }
        ticket.cancel(penaltyPercentage);
        foundFlight.availableSeats = foundFlight.availableSeats + ticket.getSeats();
        refreshFlights(foundFlight);
        return penaltyPercentage ;
    }
    // Modifier for "OwnerOnly" function
    modifier onlyOwner() {
        require(msg.sender == owner, "**  Error  ** : Only Airline Owner Account(contract deployer) allowed for this Action");
        _;
    }
    // 1st Step after deployment 
    // Only after this step, the Airline can be registered with BookingServer
    // "OwnerOnly" function, can be invoked only by the account deployed this contract
    function scheduleFlights() public onlyOwner returns(string memory)
    {
        if(isScheduled){
            emit AirlineEvent("Already scheduled. Invoke getOperableFlights to display the list of scheduled flights");
            revert("Already scheduled. Invoke getOperableFlights to display the list of scheduled flights");
        }        
        string memory returnString;
        uint i;
        uint today = block.timestamp + 1 days; 
        Flight memory tempFlight;
        string memory name ;
        string memory id ;
        uint rollingDay = TimeStampUtility.toTimestamp(TimeStampUtility.getYear(today),TimeStampUtility.getMonth(today),TimeStampUtility.getDay(today),5,30,0);
        for(i = 0; i < _from.length ; i++){
            name = string(abi.encodePacked(_from[i],":",_to[i],":",uint8(i % 10 + 48))) ;
            id = string(abi.encodePacked(name,":",Strings.uintToString(rollingDay)));
            tempFlight = Flight({
                flightName:name,
                flightInstanceIdentifier:id,
                scheduledDeparture:rollingDay,
                scheduledArrival:rollingDay + 2 hours,
                actualDeparture:0,
                actualArrival:0,
                flightStatus:flightState.Scheduled,
                availableSeats:90,
                arrayIndex:i
                });
                scheduledFlights.push(tempFlight);
        }
        isScheduled = true;
        for(i = 0 ; i < scheduledFlights.length ; i++){
            returnString = string(abi.encodePacked(returnString," [",scheduledFlights[i].flightInstanceIdentifier,"] "));
        }
        emit AirlineEvent(returnString);
        return returnString;
    }   
    // TBD: NICE to HAVE: Ontime, Delay can only be updated prior 2 hours of departure time
    // TBD: NICE to HAVE: Completed can only be updated after actualArrival time
    // TBD: NICE to HAVE: Operationally Cancelled will be updated before actualDeparture time
    // "OwnerOnly" function, can be invoked only by the account deployed this contract
    function cancelFlight(string memory _flightID) public onlyOwner returns(Flight memory) {
        uint8 i;
        Flight memory foundFlight;
        //Cancel only if they were not completed or cancelled already
        foundFlight = findFlightNotCancelledCompleted(_flightID);
        foundFlight.flightStatus = flightState.Cancelled;
        foundFlight.actualDeparture = 0;
        foundFlight.actualArrival = 0;
        Ticket[] memory tickets = m_flightTotalTicket[_flightID];
        for(i=0; i < tickets.length; i++){
            tickets[i].cancelByAirline();
        }
        refreshFlights(foundFlight);
        return foundFlight;
    }   
    // "OwnerOnly" function, can be invoked only by the account deployed this contract
    // Delay of upto hours and above 4 hours have different penalty slabs, taken care in the Ticket
    // Note : A flight can be delayed many times and the above rule is applicable for the cumulative time and this is handled by the Ticket 
    function delayFlight(uint _delayMinutes, string memory _flightID) public onlyOwner returns(Flight memory){
        uint delayTimeInSeconds = _delayMinutes * 60;
        uint timeDifference = 0;
        uint8 i;
        Flight memory foundFlight;
        foundFlight = findFlightNotCancelledCompleted(_flightID);
        // set the flight status
        foundFlight.flightStatus = flightState.Delayed;
        if (foundFlight.actualDeparture == 0){
            foundFlight.actualDeparture = foundFlight.scheduledDeparture;
            foundFlight.actualArrival = foundFlight.scheduledArrival;    
        } 
        foundFlight.actualDeparture = foundFlight.actualDeparture + delayTimeInSeconds;
        foundFlight.actualArrival = foundFlight.actualArrival + delayTimeInSeconds;
        timeDifference = foundFlight.actualDeparture - foundFlight.scheduledDeparture;
        Ticket[] memory tickets = m_flightTotalTicket[_flightID];
        for(i = 0; i < tickets.length; i ++){
            tickets[i].delayRefund(timeDifference);
        }
        refreshFlights(foundFlight);
        return foundFlight;    
    }
    // "OwnerOnly" function, can be invoked only by the account deployed this contract
    function onTimeFlight(string memory _flightID) public onlyOwner returns(Flight memory){
        // update the status of the flights and tickets
        Flight memory foundFlight;
        foundFlight = findFlightNotCancelledCompleted(_flightID);
        uint i;
        //Flight can be updated "ontime" only if they are not  in ontime, cancelled or completed 
        if (foundFlight.flightStatus == flightState.Ontime){
            emit AirlineEvent(string(abi.encodePacked("** Error **: Flight either already ONTIME" ,_flightID)));
            revert(string(abi.encodePacked("** Error **: Flight either already ONTIME" ,_flightID)));
        }
        foundFlight.flightStatus = flightState.Ontime;
        foundFlight.actualDeparture = foundFlight.scheduledDeparture;
        foundFlight.actualArrival = foundFlight.scheduledArrival;
        Ticket[] memory tickets = m_flightTotalTicket[_flightID];
        for(i = 0; i < tickets.length; i++){
            tickets[i].updateActualDeparture(foundFlight.actualDeparture);
        }
        refreshFlights(foundFlight);
        return foundFlight;
    }
    // "OwnerOnly" function, can be invoked only by the account deployed this contract
    function completeFlight(string memory _flightID) public onlyOwner returns(Flight memory){
        uint i;
        Flight memory foundFlight;
        foundFlight = findFlightNotCancelledCompleted(_flightID);
        foundFlight.flightStatus = flightState.Completed;
        Ticket[] memory tickets = m_flightTotalTicket[_flightID];
        for(i=0; i < tickets.length; i++){
            tickets[i].completeJourney();
        }
        refreshFlights(foundFlight);
        return foundFlight;
        // TBD: NICE TO HAVE: Update should be only after the scheduled departure time
        // TBD: NICE TO HAVE:  remove from the scheudled flights
    }
    // "OwnerOnly" function, can be invoked only by the account deployed this contract
    // To be invoked time to time to trasnfer money from contract account to the owner account
    function transferBalanceToOwner() public onlyOwner returns(uint){
        address payable airlineAccount = payable(owner);
        address payable contractAccount = payable(address(this)); 
        uint transferAmount = contractAccount.balance;
        airlineAccount.transfer(transferAmount);
        return transferAmount; 
    } 
    // "OwnerOnly" function, can be invoked only by the account deployed this contract
    function contractBalanceAirline() public onlyOwner view returns(uint){
        address payable contractAccount = payable(address(this)); 
        return(contractAccount.balance);
    } 
     function accountBalanceAirline() public onlyOwner view returns(uint){
        return(msg.sender.balance);
    } 
    // This function is a callback by Ticket to get the authorisation from the Airline 
    function authoriseTicket() pure external returns(bool){
        return(true);
    }
    function getAddress() public view returns(address, string memory){
        return(payable(address(this)),airlineName);
    }
    function findFlight(string memory _flightID) public view returns(Flight memory flight){
        bool foundResult;
        uint8 i;
        for(i = 0; i < scheduledFlights.length; i++){
            if(Strings.compareStrings(scheduledFlights[i].flightInstanceIdentifier,_flightID)){
                flight = scheduledFlights[i];
                foundResult = true;
                break;
            } 
        }
        if (foundResult == false){
            revert(string(abi.encodePacked("**  Error  ** : Requested Flight :: ",_flightID,":: NOT FOUND")));
        }
   }   
    receive() external payable{
    }
    fallback() external payable{
    }   
}
